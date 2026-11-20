import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Belleğdeki geçerli jeton. Oturum yöneticisi yazar, istemci okur
/// (her istekte güvenli depoya gitmemek için).
class AuthTokenHolder {
  String? token;
}

/// İstek ek anahtarları (`Options.extra`).
abstract final class ApiExtra {
  /// true ise Authorization eklenmez (giriş gibi herkese açık uçlar).
  static const noAuth = 'noAuth';

  /// true ise bu istek yeniden denenmez.
  static const noRetry = 'noRetry';

  /// true ise 401 oturumu düşürmez (giriş ucu).
  static const skipUnauthorized = 'skipUnauthorized';

  static const sentToken = '_sentToken';
  static const retryCount = '_retryCount';
}

/// Bearer + X-Client ekler; 401'de oturumu düşürmek için geri çağrı yapar.
///
/// Döngüsüz ve tek seferlik düşürme: geri çağrıya isteğin GÖNDERİLDİĞİ jeton
/// iletilir; oturum yöneticisi yalnızca bu jeton hâlâ geçerli jetonsa oturumu
/// kapatır. Böylece oturum kapandıktan sonra gelen gecikmiş 401'ler yok sayılır.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.holder, required this.onUnauthorized});

  final AuthTokenHolder holder;
  final void Function(String rejectedToken) onUnauthorized;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Web paneli kısa ömürlü "web" jetonu alır (sunucu: X-Client yoksa web); özel başlık CORS ön denetimi de gerektirmez.
    if (!kIsWeb) options.headers['X-Client'] = 'mobile';
    final token = holder.token;
    if (options.extra[ApiExtra.noAuth] != true &&
        token != null &&
        token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
      options.extra[ApiExtra.sentToken] = token;
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final sent = err.requestOptions.extra[ApiExtra.sentToken];
    if (err.response?.statusCode == 401 &&
        sent is String &&
        err.requestOptions.extra[ApiExtra.skipUnauthorized] != true) {
      onUnauthorized(sent);
    }
    handler.next(err);
  }
}

typedef DelayFn = Future<void> Function(Duration d);

/// Yalnız GÜVENLİ istekleri (GET/HEAD) yeniden dener: ağ/zaman aşımı ve 502/503/504.
/// Üstel bekleme: base * 2^deneme (+ küçük rastgele sapma). POST/PATCH/DELETE asla
/// yeniden denenmez (sözleşme §14: istekler idempotent değil, çift POST çift kayıt üretir).
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required this.dio,
    this.maxRetries = 2,
    this.baseDelay = const Duration(milliseconds: 500),
    DelayFn? delay,
    Random? random,
  }) : _delay = delay ?? ((d) => Future<void>.delayed(d)),
       _random = random ?? Random();

  final Dio dio;
  final int maxRetries;
  final Duration baseDelay;
  final DelayFn _delay;
  final Random _random;

  static bool _isSafe(String method) {
    final m = method.toUpperCase();
    return m == 'GET' || m == 'HEAD';
  }

  static bool _isRetryable(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final s = e.response?.statusCode;
        return s == 502 || s == 503 || s == 504;
      case DioExceptionType.unknown:
        return e.error != null && e.response == null;
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.transformTimeout:
        return false;
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final o = err.requestOptions;
    final attempt = (o.extra[ApiExtra.retryCount] as int?) ?? 0;
    if (!_isSafe(o.method) ||
        o.extra[ApiExtra.noRetry] == true ||
        attempt >= maxRetries ||
        !_isRetryable(err)) {
      return handler.next(err);
    }
    final wait =
        baseDelay * pow(2, attempt).toInt() +
        Duration(milliseconds: _random.nextInt(100));
    await _delay(wait);
    o.extra[ApiExtra.retryCount] = attempt + 1;
    try {
      final res = await dio.fetch<Object?>(o);
      handler.resolve(res);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
