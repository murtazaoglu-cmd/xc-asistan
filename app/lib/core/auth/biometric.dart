// İsteğe bağlı biyometrik kilit (parmak izi/yüz). Ayarlardan aç/kapa;
// uygulama arka plandan dönünce (bekleme süresinden uzunsa) kilit devreye girer.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../api/api_providers.dart';
import '../storage/storage_providers.dart';
import 'session.dart';

abstract class BiometricService {
  /// Cihazda biyometrik ya da ekran kilidi doğrulaması var mı.
  Future<bool> isSupported();

  /// Kullanıcıyı doğrular; başarı → true. Hata/iptal → false (fırlatmaz).
  Future<bool> authenticate(String reason);
}

class LocalAuthBiometricService implements BiometricService {
  LocalAuthBiometricService([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> isSupported() async {
    if (kIsWeb) return false; // Web'de biyometrik kilit yok.
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // biometricOnly false: parmak izi yoksa cihaz PIN/desen yedeği kullanılabilir.
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }
}

final biometricServiceProvider = Provider<BiometricService>(
  (ref) => LocalAuthBiometricService(),
);

@immutable
class AppLockState {
  const AppLockState({required this.enabled, required this.locked});
  final bool enabled;
  final bool locked;

  AppLockState copyWith({bool? enabled, bool? locked}) => AppLockState(
    enabled: enabled ?? this.enabled,
    locked: locked ?? this.locked,
  );
}

class AppLockNotifier extends Notifier<AppLockState> {
  DateTime? _backgroundedAt;
  bool _suspended = false;
  DateTime Function() clock = DateTime.now;

  static const String reason =
      'XC Asistan kilidini açmak için kimliğinizi doğrulayın';

  @override
  AppLockState build() {
    final enabled = ref.read(appPrefsProvider).biometricLock;
    ref.listen<SessionState>(sessionProvider, (prev, next) {
      if (next is SessionAuthenticated && prev is SessionBooting) {
        // Soğuk açılış: oturum var ve kilit açık → kilitle.
        if (state.enabled) state = state.copyWith(locked: true);
      } else if (next is! SessionAuthenticated) {
        state = state.copyWith(locked: false);
      }
    });
    return AppLockState(enabled: enabled, locked: false);
  }

  Duration get _grace => ref.read(appConfigProvider).lockGracePeriod;

  void onBackgrounded() {
    if (_suspended) return;
    _backgroundedAt = clock();
  }

  void onResumed() {
    if (_suspended) {
      _suspended = false;
      _backgroundedAt = null;
      return;
    }
    final at = _backgroundedAt;
    _backgroundedAt = null;
    if (at == null || !state.enabled) return;
    if (ref.read(sessionProvider) is! SessionAuthenticated) return;
    if (clock().difference(at) >= _grace) {
      state = state.copyWith(locked: true);
    }
  }

  /// Kamera, dosya seçici, WhatsApp gibi sistem ekranları uygulamayı arka plana atar;
  /// bu sarmalayıcı içinde dönüşte kilit istenmez.
  Future<T> runUnlocked<T>(Future<T> Function() action) async {
    _suspended = true;
    try {
      return await action();
    } finally {
      // onResumed yoksa (ör. sistem ekranı açılmadı) bayrak takılı kalmasın.
      Future<void>.delayed(
        const Duration(seconds: 2),
        () => _suspended = false,
      );
    }
  }

  /// Kilidi açma denemesi.
  Future<bool> unlock() async {
    final ok = await ref.read(biometricServiceProvider).authenticate(reason);
    if (ok) state = state.copyWith(locked: false);
    return ok;
  }

  /// Ayarlardan aç/kapa. Açarken önce kimlik doğrulanır (kendini kilitlememek için).
  /// Cihaz desteklemiyorsa false döner.
  Future<bool> setEnabled(bool value) async {
    final bio = ref.read(biometricServiceProvider);
    if (value) {
      if (!await bio.isSupported()) return false;
      if (!await bio.authenticate('Kilidi açmak için kimliğinizi doğrulayın'))
        return false;
    }
    await ref.read(appPrefsProvider).setBiometricLock(value);
    state = AppLockState(enabled: value, locked: false);
    return true;
  }
}

final appLockProvider = NotifierProvider<AppLockNotifier, AppLockState>(
  AppLockNotifier.new,
);
