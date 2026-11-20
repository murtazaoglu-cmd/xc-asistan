// FCM şimdilik YOK (Firebase hesabı yok). Sonradan eklemek için arayüz:
//   1) firebase_core + firebase_messaging ekleyin, Firebase'i main()'de başlatın.
//   2) class FcmPushService implements PushService yazın (init: izin + token,
//      currentToken: FirebaseMessaging.instance.getToken(), onTokenRefresh: stream).
//   3) pushServiceProvider'ı main()'de FcmPushService ile override edin.
// Cihaz kaydı (POST/DELETE /push/device) aşağıdaki PushDeviceRegistry ile hazırdır.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_client.dart';
import '../api/api_providers.dart';

abstract class PushService {
  /// İzin isteme + FCM başlatma (şimdilik hiçbir şey yapmaz).
  Future<void> init();

  /// Geçerli push jetonu; yoksa null.
  Future<String?> currentToken();

  /// Jeton yenilendiğinde yeni jeton.
  Stream<String> get onTokenRefresh;
}

class NoopPushService implements PushService {
  @override
  Future<void> init() async {}
  @override
  Future<String?> currentToken() async => null;
  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();
}

final pushServiceProvider = Provider<PushService>((ref) => NoopPushService());

/// Sunucuya cihaz jetonu kaydı (sözleşme §13).
class PushDeviceRegistry {
  PushDeviceRegistry(this._api, this._push);
  final ApiClient _api;
  final PushService _push;

  /// Girişte ve jeton yenilendiğinde çağrılır. Jeton yoksa sessizce çıkar. Hata fırlatmaz.
  Future<void> register() async {
    try {
      final token = await _push.currentToken();
      if (token == null || token.length < 10) return;
      String? version;
      try {
        version = (await PackageInfo.fromPlatform()).version;
      } catch (_) {}
      await _api.post(
        '/push/device',
        data: {
          'token': token,
          'platform': defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
          if (version != null) 'app_version': version,
        },
      );
    } catch (_) {}
  }

  /// Çıkışta: DELETE /push/device. Jeton yoksa çağrı yapılmaz. Hata fırlatmaz.
  Future<void> unregister() async {
    try {
      final token = await _push.currentToken();
      if (token == null) return;
      await _api.delete('/push/device', data: {'token': token});
    } catch (_) {}
  }
}

final pushDeviceRegistryProvider = Provider<PushDeviceRegistry>(
  (ref) => PushDeviceRegistry(
    ref.watch(apiClientProvider),
    ref.watch(pushServiceProvider),
  ),
);
