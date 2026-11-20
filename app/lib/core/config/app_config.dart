// Derleme zamanı yapılandırma. Değerler --dart-define ile değiştirilir:
//   flutter run --dart-define=API_BASE_URL=https://api.controlx.com.tr/api
//   flutter run --dart-define=DEMO=true          (backend'siz, bellekte örnek veri)
//   flutter build apk --dart-define=FORCE_UPDATE_ENABLED=true
import 'package:flutter/foundation.dart';

@immutable
class AppConfig {
  const AppConfig({
    this.apiBaseUrl = defaultApiBaseUrl,
    this.demo = false,
    this.forceUpdateEnabled = false,
    this.storeUrl = '',
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.maxRetries = 2,
    this.retryBaseDelay = const Duration(milliseconds: 500),
    this.lockGracePeriod = const Duration(seconds: 30),
  });

  static const String defaultApiBaseUrl = 'https://api.controlx.com.tr/api';

  factory AppConfig.fromEnvironment() {
    const base = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: defaultApiBaseUrl,
    );
    return AppConfig(
      apiBaseUrl: _normalizeBase(base),
      demo: const bool.fromEnvironment('DEMO'),
      forceUpdateEnabled: const bool.fromEnvironment('FORCE_UPDATE_ENABLED'),
      storeUrl: const String.fromEnvironment('STORE_URL'),
    );
  }

  static String _normalizeBase(String v) {
    var s = v.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s.isEmpty ? defaultApiBaseUrl : s;
  }

  /// Taban adres (sonunda `/` yok). Tüm yollar `/auth/login` gibi `/` ile başlar.
  final String apiBaseUrl;

  /// Backend'siz demo modu (sahte API katmanı).
  final bool demo;

  /// "Zorunlu güncelleme" kancası (şimdilik pasif).
  final bool forceUpdateEnabled;
  final String storeUrl;

  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;

  /// Yalnız güvenli GET'ler için en çok yeniden deneme sayısı.
  final int maxRetries;
  final Duration retryBaseDelay;

  /// Arka plandan dönüşte biyometrik kilidin devreye girmesi için en az arka plan süresi.
  /// (Kamera/dosya seçici gibi sistem ekranları kilitleme istemez; bkz. AppLock.runUnlocked.)
  final Duration lockGracePeriod;

  /// Geliştirici bilgisi (yer tutucu ekranlarda uç/sahip listesi) gösterilsin mi.
  bool get showDevInfo => kDebugMode || demo;
}
