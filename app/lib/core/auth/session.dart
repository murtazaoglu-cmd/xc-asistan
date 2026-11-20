// Oturum durum makinesi (Riverpod). Sözleşme §1 "önerilen akış":
//   açılış: jeton oku → GET /auth/me (200 geçerli, 401 giriş) → POST /auth/refresh (yeni jetonu sakla)
//   herhangi bir istekte 401 → jetonu sil, girişe dön (TEK SEFERLİK, döngüsüz)
//   çıkış: DELETE /push/device → yerel silme;  logout-all: POST /auth/logout-all
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../api/api_providers.dart';
import '../notifications/notification_providers.dart';
import '../notifications/push_service.dart';
import '../storage/storage_providers.dart';
import 'auth_models.dart';
import 'auth_repository.dart';

@immutable
sealed class SessionState {
  const SessionState();
}

/// Uygulama açılıyor, jeton doğrulanıyor.
class SessionBooting extends SessionState {
  const SessionBooting();
}

/// Açılışta sunucuya ulaşılamadı ve çevrimdışı önbellek yok: "Tekrar dene" gösterilir.
class SessionBootFailed extends SessionState {
  const SessionBootFailed(this.message);
  final String message;
}

class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated({this.notice, this.expired = false});

  /// Giriş ekranında gösterilecek bilgi (ör. "Oturum süresi doldu").
  final String? notice;
  final bool expired;
}

class SessionAuthenticated extends SessionState {
  const SessionAuthenticated(this.me, {this.offline = false});
  final MeResponse me;

  /// Sunucuya ulaşılamadan önbellekteki kullanıcıyla açıldı.
  final bool offline;

  AuthUser get user => me.user;
  AppCapabilities get capabilities => me.capabilities;
}

const String sessionExpiredMessage =
    'Oturum süresi doldu. Lütfen tekrar giriş yapın.';

class SessionNotifier extends Notifier<SessionState> {
  Future<void>? _boot;
  DateTime? _lastRefresh;

  /// Yenileme en sık bu aralıkla yapılır (uygulamaya her dönüşte değil).
  static const Duration refreshInterval = Duration(hours: 12);

  AuthRepository get _repo => ref.read(authRepositoryProvider);
  String? get currentToken => ref.read(tokenHolderProvider).token;

  @override
  SessionState build() {
    // 401 kancasını bağla (API katmanı oturumu doğrudan bilmez).
    final bridge = ref.read(unauthorizedBridgeProvider);
    bridge.handler = onTokenRejected;
    ref.onDispose(() => bridge.handler = null);
    scheduleMicrotask(() {
      if (ref.mounted) bootstrap();
    });
    return const SessionBooting();
  }

  /// Açılış akışı. Birden çok çağrı aynı işi paylaşır (idempotent).
  Future<void> bootstrap() => _boot ??= _runBootstrap();

  Future<void> retryBootstrap() {
    _boot = null;
    state = const SessionBooting();
    return bootstrap();
  }

  Future<void> _runBootstrap() async {
    final store = ref.read(tokenStoreProvider);
    final holder = ref.read(tokenHolderProvider);
    final token = await store.readToken();
    if (token == null || token.isEmpty) {
      state = const SessionUnauthenticated();
      return;
    }
    holder.token = token;
    try {
      final me = await _repo.me();
      state = SessionAuthenticated(me);
      await _cacheMe(me);
    } on AppException catch (e) {
      if (e.isUnauthorized) {
        await _clearLocal();
        state = const SessionUnauthenticated(
          notice: sessionExpiredMessage,
          expired: true,
        );
        return;
      }
      // Ağ/sunucu sorunu: önbellekteki kullanıcıyla çevrimdışı aç, yoksa "tekrar dene".
      final cached = await _readCachedMe();
      if (cached != null) {
        state = SessionAuthenticated(cached, offline: true);
      } else {
        holder.token = null;
        state = SessionBootFailed(e.message);
      }
      return;
    }
    unawaited(_refreshToken());
    unawaited(_registerPush());
  }

  /// POST /auth/refresh: kayan 30 günlük oturum için yeni jetonu sakla. Hata sessizdir
  /// (401'i zaten interceptor işler).
  Future<void> _refreshToken() async {
    try {
      final r = await _repo.refresh();
      if (r.token.isEmpty) return;
      if (state is! SessionAuthenticated) return;
      ref.read(tokenHolderProvider).token = r.token;
      await ref.read(tokenStoreProvider).writeToken(r.token);
      _lastRefresh = DateTime.now();
    } catch (_) {}
  }

  Future<void> _registerPush() =>
      ref.read(pushDeviceRegistryProvider).register();

  /// Uygulama ön plana dönünce: uzun süredir yenilenmediyse jetonu yenile.
  Future<void> onAppResumed() async {
    if (state is! SessionAuthenticated) return;
    final last = _lastRefresh;
    if (last == null || DateTime.now().difference(last) >= refreshInterval) {
      await _refreshToken();
    }
  }

  /// Oturum açar. Hata → [AppException] fırlatır (durum değişmez; arayüz mesajı gösterir).
  Future<void> login(String email, String password) async {
    final r = await _repo.login(email, password);
    final store = ref.read(tokenStoreProvider);
    ref.read(tokenHolderProvider).token = r.token;
    await store.writeToken(r.token);
    MeResponse me;
    try {
      me = await _repo.me();
    } catch (_) {
      final u = r.user;
      if (u == null) {
        await _clearLocal();
        rethrow;
      }
      me = MeResponse.fromUser(u, expiresAt: r.expiresAt);
    }
    await _cacheMe(me);
    await ref.read(appPrefsProvider).setLastEmail(email.trim());
    _lastRefresh = DateTime.now();
    state = SessionAuthenticated(me);
    unawaited(_registerPush());
  }

  /// Şifre değişikliğinden sonra: sunucu eski jetonları iptal eder, yanıttaki YENİ jetonu saklar
  /// (sözleşme §12 `PATCH /users/me/password`). Oturum açık değilse yok sayılır.
  Future<void> adoptToken(String token) async {
    if (state is! SessionAuthenticated || token.isEmpty) return;
    ref.read(tokenHolderProvider).token = token;
    await ref.read(tokenStoreProvider).writeToken(token);
    _lastRefresh = DateTime.now();
    unawaited(
      _registerPush(),
    ); // eski cihaz kayıtları iptal oldu: FCM jetonunu yeniden kaydet
  }

  /// Çıkış: önce DELETE /push/device, sonra yerel silme (ağ hatası çıkışı engellemez).
  Future<void> logout() async {
    await ref
        .read(pushDeviceRegistryProvider)
        .unregister()
        .timeout(const Duration(seconds: 5), onTimeout: () {});
    await _finishLogout();
  }

  /// Tüm cihazlardan çıkış. Sunucu isteği başarısızsa hata fırlatır (oturum KORUNUR).
  Future<void> logoutAll() async {
    await _repo.logoutAll();
    await _finishLogout();
  }

  Future<void> _finishLogout() async {
    await _clearLocal();
    try {
      await ref.read(notificationServiceProvider).cancelAll();
    } catch (_) {}
    state = const SessionUnauthenticated();
  }

  /// API katmanı 401 aldığında çağırır. Yalnızca REDDEDİLEN jeton hâlâ geçerli jetonsa
  /// ve oturum açıksa oturumu düşürür: tek seferlik, döngüsüz.
  void onTokenRejected(String rejectedToken) {
    if (state is! SessionAuthenticated) return;
    if (rejectedToken != currentToken) return;
    unawaited(_expire());
  }

  Future<void> _expire() async {
    await _clearLocal();
    state = const SessionUnauthenticated(
      notice: sessionExpiredMessage,
      expired: true,
    );
  }

  /// /auth/me'yi yeniden okur (rol/yetki değişikliği yansısın).
  Future<void> reloadMe() async {
    if (state is! SessionAuthenticated) return;
    try {
      final me = await _repo.me();
      if (state is SessionAuthenticated) {
        state = SessionAuthenticated(me);
        await _cacheMe(me);
      }
    } catch (_) {}
  }

  Future<void> _clearLocal() async {
    ref.read(tokenHolderProvider).token = null;
    _lastRefresh = null;
    await ref.read(tokenStoreProvider).clear();
  }

  Future<void> _cacheMe(MeResponse me) async {
    try {
      await ref.read(tokenStoreProvider).writeMeCache(jsonEncode(me.toJson()));
    } catch (_) {}
  }

  Future<MeResponse?> _readCachedMe() async {
    try {
      final s = await ref.read(tokenStoreProvider).readMeCache();
      if (s == null) return null;
      final d = jsonDecode(s);
      if (d is! Map) return null;
      return MeResponse.fromJson(d.map((k, v) => MapEntry(k.toString(), v)));
    } catch (_) {
      return null;
    }
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

/// Giriş yapmış kullanıcının yetenekleri (yoksa null).
final capabilitiesProvider = Provider<AppCapabilities?>((ref) {
  final s = ref.watch(sessionProvider);
  return s is SessionAuthenticated ? s.capabilities : null;
});

final currentUserProvider = Provider<AuthUser?>((ref) {
  final s = ref.watch(sessionProvider);
  return s is SessionAuthenticated ? s.user : null;
});
