// Tek hata türü: tüm ağ/sunucu hataları AppException'a çevrilir. Arayüz yalnızca
// `message` (Türkçe, kullanıcıya gösterilebilir) ve `code` ile ilgilenir.
// Sunucudaki ham hata ayrıntısı (SQL vb.) kullanıcıya ASLA gösterilmez (5xx maskelenir).
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum AppErrorCode {
  unauthorized,
  forbidden,
  validation,
  notFound,
  conflict,
  rateLimit,
  network,
  server,
  unknown,
}

@immutable
class AppException implements Exception {
  const AppException(
    this.code,
    this.message, {
    this.statusCode,
    this.body,
    this.cause,
  });

  final AppErrorCode code;

  /// Türkçe, kullanıcıya gösterilebilir mesaj.
  final String message;
  final int? statusCode;

  /// Sunucu yanıt gövdesi (ek alanlar için; ör. gönderimde `sent:false`).
  final Object? body;
  final Object? cause;

  bool get isUnauthorized => code == AppErrorCode.unauthorized;
  bool get isNetwork => code == AppErrorCode.network;
  bool get isRetryable =>
      code == AppErrorCode.network || code == AppErrorCode.server;

  static const String networkMessage =
      'İnternet bağlantısı yok ya da sunucuya ulaşılamıyor. Bağlantınızı kontrol edip tekrar deneyin.';
  static const String timeoutMessage =
      'Sunucu zamanında yanıt vermedi. Lütfen tekrar deneyin.';
  static const String serverMessage =
      'Sunucuda bir sorun oluştu. Lütfen biraz sonra tekrar deneyin.';
  static const String unknownMessage =
      'Beklenmeyen bir sorun oluştu. Lütfen tekrar deneyin.';

  /// Durum kodu + gövdeden hata üretir (sözleşme §0 durum kodları).
  factory AppException.fromResponse(
    int? status,
    Object? body, {
    Object? cause,
  }) {
    final serverMsg = _extractMessage(body);
    AppErrorCode code;
    String fallback;
    switch (status) {
      case 400:
      case 422:
        code = AppErrorCode.validation;
        fallback = 'Geçersiz veya eksik değer girildi.';
      case 401:
        code = AppErrorCode.unauthorized;
        fallback = 'Oturum süresi doldu. Lütfen tekrar giriş yapın.';
      case 403:
        code = AppErrorCode.forbidden;
        fallback = 'Bu işlem için yetkiniz yok.';
      case 404:
        code = AppErrorCode.notFound;
        fallback = 'Kayıt bulunamadı.';
      case 409:
        code = AppErrorCode.conflict;
        fallback = 'Bu kayıt zaten var ya da başka kayıtlarla ilişkili.';
      case 413:
        code = AppErrorCode.validation;
        fallback = 'Dosya veya istek çok büyük.';
      case 429:
        code = AppErrorCode.rateLimit;
        fallback =
            'Çok fazla deneme yapıldı. Lütfen biraz bekleyip tekrar deneyin.';
      default:
        if (status != null && status >= 500) {
          // Sunucu hata ayrıntısı (SQL vb.) kullanıcıya gösterilmez.
          return AppException(
            AppErrorCode.server,
            serverMessage,
            statusCode: status,
            body: body,
            cause: cause,
          );
        }
        code = AppErrorCode.unknown;
        fallback = unknownMessage;
    }
    // 413'te sunucu mesajı yerine sabit Türkçe metin; diğerlerinde sunucunun Türkçe mesajı.
    final msg = (status == 413) ? fallback : (serverMsg ?? fallback);
    return AppException(
      code,
      msg,
      statusCode: status,
      body: body,
      cause: cause,
    );
  }

  /// Dio hatasını çevirir.
  factory AppException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return AppException(AppErrorCode.network, timeoutMessage, cause: e);
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return AppException(
          AppErrorCode.network,
          e.type == DioExceptionType.badCertificate
              ? 'Güvenli bağlantı kurulamadı.'
              : networkMessage,
          cause: e,
        );
      case DioExceptionType.cancel:
        return AppException(
          AppErrorCode.unknown,
          'İstek iptal edildi.',
          cause: e,
        );
      case DioExceptionType.badResponse:
        return AppException.fromResponse(
          e.response?.statusCode,
          e.response?.data,
          cause: e,
        );
      case DioExceptionType.unknown:
        final err = e.error;
        if (err is SocketException ||
            err is HandshakeException ||
            err is TimeoutException) {
          return AppException(AppErrorCode.network, networkMessage, cause: e);
        }
        if (err is AppException) return err;
        return AppException(AppErrorCode.unknown, unknownMessage, cause: e);
    }
  }

  /// Herhangi bir hatayı AppException'a çevirir (arayüz için tek giriş noktası).
  static AppException from(Object error) {
    if (error is AppException) return error;
    if (error is DioException) return AppException.fromDio(error);
    if (error is SocketException || error is TimeoutException) {
      return AppException(AppErrorCode.network, networkMessage, cause: error);
    }
    return AppException(AppErrorCode.unknown, unknownMessage, cause: error);
  }

  static String? _extractMessage(Object? body) {
    if (body is Map) {
      final e = body['error'] ?? body['message'];
      if (e is String && e.trim().isNotEmpty) return e.trim();
    }
    return null;
  }

  @override
  String toString() => 'AppException($code, $statusCode, $message)';
}
