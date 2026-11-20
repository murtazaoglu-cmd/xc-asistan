import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../demo/demo_adapter.dart';
import 'api_client.dart';
import 'interceptors.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

final tokenHolderProvider = Provider<AuthTokenHolder>(
  (ref) => AuthTokenHolder(),
);

/// 401 geldiğinde çağrılır. Oturum yöneticisi `main`/uygulama köküne bağlar
/// (döngüsel bağımlılığı önlemek için tek yönlü kanca).
class UnauthorizedBridge {
  void Function(String rejectedToken)? handler;
}

final unauthorizedBridgeProvider = Provider<UnauthorizedBridge>(
  (ref) => UnauthorizedBridge(),
);

/// Dio örneği. DEMO modunda gerçek ağ yerine bellek içi sahte API kullanılır.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final holder = ref.watch(tokenHolderProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      sendTimeout: config.sendTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      headers: {'Accept': 'application/json'},
    ),
  );
  if (config.demo) {
    dio.httpClientAdapter = ref.watch(demoAdapterProvider);
  }
  dio.interceptors.addAll([
    AuthInterceptor(
      holder: holder,
      onUnauthorized: (t) =>
          ref.read(unauthorizedBridgeProvider).handler?.call(t),
    ),
    RetryInterceptor(
      dio: dio,
      maxRetries: config.maxRetries,
      baseDelay: config.retryBaseDelay,
    ),
  ]);
  return dio;
});

/// Tüm repository'ler API'ye BUNUNLA erişir.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(dioProvider)),
);
