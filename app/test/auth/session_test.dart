import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/api/api_providers.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/auth/session.dart';
import 'package:xc_asistan/core/notifications/push_service.dart';
import 'package:xc_asistan/core/storage/storage_providers.dart';
import 'package:xc_asistan/core/storage/token_store.dart';

import '../helpers/fakes.dart';

// ignore_for_file: library_private_types_in_public_api
class _Env {
  _Env(this.container, this.repo, this.store, this.gateway);
  final ProviderContainer container;
  final FakeAuthRepository repo;
  final MemoryTokenStore store;
  final FakeNotificationsGateway gateway;
  SessionNotifier get notifier => container.read(sessionProvider.notifier);
  SessionState get state => container.read(sessionProvider);
  String? get holderToken => container.read(tokenHolderProvider).token;
}

Future<_Env> env({
  String? storedToken,
  String? pushToken,
  FakeAuthRepository? repo,
}) async {
  final r = repo ?? FakeAuthRepository();
  final store = MemoryTokenStore()..token = storedToken;
  final gateway = FakeNotificationsGateway();
  final c = ProviderContainer(
    overrides: await baseOverrides(
      repo: r,
      store: store,
      gateway: gateway,
      pushToken: pushToken,
    ),
  );
  addTearDown(c.dispose);
  return _Env(c, r, store, gateway);
}

void main() {
  group('açılış akışı (sözleşme §1 adım 2-3)', () {
    test('jeton yok → girişsiz', () async {
      final e = await env();
      await e.notifier.bootstrap();
      expect(e.state, isA<SessionUnauthenticated>());
      expect(e.repo.calls, isEmpty);
    });

    test('jeton var → /auth/me 200 → oturum açık, sonra /auth/refresh yeni jetonu saklar', () async {
      final e = await env(storedToken: 'old');
      await e.notifier.bootstrap();
      await Future<void>.delayed(Duration.zero);
      expect(e.state, isA<SessionAuthenticated>());
      expect(e.repo.calls.take(2), ['me', 'refresh']);
      expect(e.store.token, 'tok-refreshed');
      expect(e.holderToken, 'tok-refreshed');
      expect(e.store.me, isNotNull); // çevrimdışı önbellek
    });

    test(
      'me 401 → jeton silinir, girişe "oturum süresi doldu" bildirimiyle',
      () async {
        final e = await env(storedToken: 'old');
        e.repo.meError = ex(AppErrorCode.unauthorized);
        await e.notifier.bootstrap();
        final s = e.state as SessionUnauthenticated;
        expect(s.expired, isTrue);
        expect(s.notice, sessionExpiredMessage);
        expect(e.store.token, isNull);
        expect(e.holderToken, isNull);
        expect(e.repo.calls.contains('refresh'), isFalse);
      },
    );

    test(
      'ağ hatası + önbellek yok → BootFailed; yeniden deneyince açılır',
      () async {
        final e = await env(storedToken: 'old');
        e.repo.meError = ex(AppErrorCode.network, 'çevrimdışı');
        await e.notifier.bootstrap();
        expect(e.state, isA<SessionBootFailed>());
        expect((e.state as SessionBootFailed).message, 'çevrimdışı');
        e.repo.meError = null;
        await e.notifier.retryBootstrap();
        expect(e.state, isA<SessionAuthenticated>());
      },
    );

    test('ağ hatası + önbellek var → çevrimdışı oturum', () async {
      final e = await env(storedToken: 'old');
      await e.notifier.bootstrap(); // önbelleği doldurur
      final e2 = await env(storedToken: 'old');
      e2.store.me = e.store.me;
      e2.repo.meError = ex(AppErrorCode.network);
      await e2.notifier.bootstrap();
      final s = e2.state as SessionAuthenticated;
      expect(s.offline, isTrue);
      expect(s.user.email, 'a@x.com');
    });

    test('refresh hatası oturumu bozmaz', () async {
      final e = await env(storedToken: 'old');
      e.repo.refreshError = ex(AppErrorCode.network);
      await e.notifier.bootstrap();
      await Future<void>.delayed(Duration.zero);
      expect(e.state, isA<SessionAuthenticated>());
      expect(e.store.token, 'old');
    });

    test('bootstrap idempotent: aynı işi paylaşır', () async {
      final e = await env(storedToken: 'old');
      await Future.wait([e.notifier.bootstrap(), e.notifier.bootstrap()]);
      expect(e.repo.calls.where((c) => c == 'me').length, 1);
    });
  });

  group('giriş / çıkış', () {
    test(
      'login: jeton güvenli depoda, /auth/me ile yetkiler, son e-posta kaydı',
      () async {
        final e = await env();
        await e.notifier.bootstrap();
        await e.notifier.login('a@x.com', 'pw');
        expect(e.state, isA<SessionAuthenticated>());
        expect(e.store.token, 'tok-login');
        expect(e.holderToken, 'tok-login');
        expect(e.repo.calls, containsAllInOrder(['login:a@x.com', 'me']));
        expect(e.container.read(appPrefsProvider).lastEmail, 'a@x.com');
      },
    );

    test('login hatası: durum değişmez, hata fırlar', () async {
      final e = await env();
      await e.notifier.bootstrap();
      e.repo.loginError = ex(
        AppErrorCode.unauthorized,
        'E-posta veya şifre hatalı.',
      );
      await expectLater(
        e.notifier.login('a@x.com', 'x'),
        throwsA(
          isA<AppException>().having(
            (x) => x.message,
            'msg',
            'E-posta veya şifre hatalı.',
          ),
        ),
      );
      expect(e.state, isA<SessionUnauthenticated>());
      expect(e.store.token, isNull);
    });

    test('login sonrası /auth/me düşerse kullanıcıdan türetilir', () async {
      final e = await env();
      await e.notifier.bootstrap();
      e.repo.meError = ex(AppErrorCode.network);
      await e.notifier.login('a@x.com', 'pw');
      expect(e.state, isA<SessionAuthenticated>());
      expect(e.container.read(capabilitiesProvider)!.role, UserRole.admin);
    });

    test(
      'çıkış: önce DELETE /push/device, sonra yerel silme; bildirimler iptal',
      () async {
        final e = await env(storedToken: 'old', pushToken: 'fcm-token-12345');
        final calls = <String>[];
        final c = ProviderContainer(
          overrides: [
            ...await baseOverrides(
              repo: e.repo,
              store: e.store,
              gateway: e.gateway,
            ),
            pushDeviceRegistryProvider.overrideWithValue(
              _RecordingRegistry(calls, e.store),
            ),
          ],
        );
        addTearDown(c.dispose);
        await c.read(sessionProvider.notifier).bootstrap();
        await c.read(sessionProvider.notifier).logout();
        expect(calls, ['unregister(token still present: true)']);
        expect(e.store.token, isNull);
        expect(c.read(tokenHolderProvider).token, isNull);
        expect(c.read(sessionProvider), isA<SessionUnauthenticated>());
        expect(e.gateway.log, contains('cancelAll'));
      },
    );

    test('logout-all sunucuya gider, sonra yerel silme; hata olursa oturum korunur', () async {
      final e = await env(storedToken: 'old');
      await e.notifier.bootstrap();
      e.repo.logoutAllError = ex(AppErrorCode.network);
      await expectLater(e.notifier.logoutAll(), throwsA(isA<AppException>()));
      expect(e.state, isA<SessionAuthenticated>());
      expect(e.store.token, isNotNull);
      e.repo.logoutAllError = null;
      await e.notifier.logoutAll();
      expect(e.state, isA<SessionUnauthenticated>());
      expect(e.store.token, isNull);
    });
  });

  group('401 → oturumu düşür (tek seferlik, döngüsüz)', () {
    test('geçerli jetonun reddi oturumu kapatır; tekrarı etkisiz', () async {
      final e = await env(storedToken: 'old');
      await e.notifier.bootstrap();
      await Future<void>.delayed(Duration.zero);
      final tok = e.holderToken!;
      e.notifier.onTokenRejected(tok);
      await Future<void>.delayed(Duration.zero);
      final s = e.state as SessionUnauthenticated;
      expect(s.expired, isTrue);
      expect(e.store.token, isNull);
      // ikinci (gecikmiş) 401: durum zaten girişsiz; hiçbir şey olmaz
      final before = e.state;
      e.notifier.onTokenRejected(tok);
      await Future<void>.delayed(Duration.zero);
      expect(identical(e.state, before), isTrue);
    });

    test('eski jetonla gelen 401 yeni oturumu düşürmez', () async {
      final e = await env(storedToken: 'old');
      await e.notifier.bootstrap();
      await Future<void>.delayed(Duration.zero);
      e.notifier.onTokenRejected('baska-eski-jeton');
      await Future<void>.delayed(Duration.zero);
      expect(e.state, isA<SessionAuthenticated>());
    });

    test(
      'açılış sırasındaki 401 oturum kancasını tetiklemez (boot kendisi işler)',
      () async {
        final e = await env(storedToken: 'old');
        final gate = Completer<void>();
        e.repo.meGate = gate;
        final boot = e.notifier.bootstrap();
        await Future<void>.delayed(Duration.zero);
        e.notifier.onTokenRejected('old'); // Booting iken
        expect(e.state, isA<SessionBooting>());
        gate.complete();
        await boot;
        expect(e.state, isA<SessionAuthenticated>());
      },
    );
  });

  group('capabilities (role dayalı)', () {
    test('saha: hepsi false, sade kabuk', () {
      final c = AppCapabilities.forRole(UserRole.saha);
      expect(c.isField, isTrue);
      expect([
        c.showJobs,
        c.showAssistant,
        c.showCustomers,
        c.showFinance,
        c.showStock,
        c.showReports,
        c.showInvoicesVat,
      ], everyElement(isFalse));
    });

    test('personel: teklif/proje/finans var, müşteri yok (sözleşme §1)', () {
      final c = AppCapabilities.forRole(UserRole.personel);
      expect(c.showJobs, isTrue);
      expect(c.showFinance, isTrue);
      expect(c.showCustomers, isFalse);
      expect(c.showInvoicesVat, isFalse);
      expect(c.manageUsers, isFalse);
    });

    test('sunucu capabilities alanı esas alınır; saha sunucu true dese bile sade kalır', () {
      final me = MeResponse.fromJson({
        'user': {'id': '1', 'name': 'S', 'email': 's@x.com', 'role': 'saha'},
        'capabilities': {'offers': true, 'finance': true, 'customers': true},
      });
      expect(me.capabilities.showJobs, isFalse);
      expect(me.capabilities.showFinance, isFalse);
    });

    test('bilinmeyen rol en kısıtlı rola düşer', () {
      expect(
        AuthUser.fromJson({'id': '1', 'role': 'tanimsiz'}).role,
        UserRole.saha,
      );
    });

    test('me ayrıştırma: lider, ekip, oturum', () {
      final me = MeResponse.fromJson({
        'user': {
          'id': '1',
          'name': 'OrtakA',
          'email': 'oa@x.com',
          'role': 'ortak',
        },
        'leader': {'id': '2', 'name': 'Admin', 'role': 'admin'},
        'team': [
          {'id': '3', 'name': 'PersA', 'role': 'personel'},
        ],
        'capabilities': {
          'offers': true,
          'customers': true,
          'finance': true,
          'materials': true,
        },
        'session': {
          'client': 'mobile',
          'expiresAt': '2026-12-20T16:11:11.000Z',
        },
      });
      expect(me.leader!.name, 'Admin');
      expect(me.team.single.role, 'personel');
      expect(me.sessionExpiresAt, DateTime.utc(2026, 12, 20, 16, 11, 11));
      expect(me.capabilities.showCustomers, isTrue);
      // gidiş-dönüş (çevrimdışı önbellek)
      final again = MeResponse.fromJson(me.toJson());
      expect(again.user.email, 'oa@x.com');
      expect(again.capabilities.showStock, isTrue);
    });
  });
}

class _RecordingRegistry implements PushDeviceRegistry {
  _RecordingRegistry(this.calls, this.store);
  final List<String> calls;
  final MemoryTokenStore store;
  @override
  Future<void> register() async {}
  @override
  Future<void> unregister() async =>
      calls.add('unregister(token still present: ${store.token != null})');
}
