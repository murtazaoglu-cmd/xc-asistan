// Kimlik doğrulama uçları (sözleşme §1 ve §13 push cihaz kaydı).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/api_providers.dart';
import '../api/interceptors.dart';
import 'auth_models.dart';

abstract class AuthRepository {
  Future<TokenResult> login(String email, String password);
  Future<MeResponse> me();
  Future<TokenResult> refresh();
  Future<void> logoutAll();

  /// `DELETE /push/device` — çıkışta çağrılır.
  Future<void> unregisterDevice(String pushToken);
}

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._api);
  final ApiClient _api;

  @override
  Future<TokenResult> login(String email, String password) async {
    final res = await _api.send(
      'POST',
      '/auth/login',
      data: {
        'email': email.trim(),
        'password': password,
        'client': kIsWeb ? 'web' : 'mobile',
      },
      extra: {
        ApiExtra.noAuth: true,
        ApiExtra.skipUnauthorized: true,
        ApiExtra.noRetry: true,
      },
    );
    final r = TokenResult.fromJson(res.map);
    if (r.token.isEmpty) {
      throw const AppException(
        AppErrorCode.unknown,
        AppException.unknownMessage,
      );
    }
    return r;
  }

  @override
  Future<MeResponse> me() async =>
      MeResponse.fromJson(await _api.getMap('/auth/me'));

  @override
  Future<TokenResult> refresh() async {
    final j = asMap(await _api.post('/auth/refresh'));
    return TokenResult.fromJson(j);
  }

  @override
  Future<void> logoutAll() async {
    await _api.post('/auth/logout-all');
  }

  @override
  Future<void> unregisterDevice(String pushToken) async {
    await _api.delete('/push/device', data: {'token': pushToken});
  }

  static Map<String, dynamic> asMap(Object? v) => v is Map
      ? v.map((k, val) => MapEntry(k.toString(), val))
      : <String, dynamic>{};
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => HttpAuthRepository(ref.watch(apiClientProvider)),
);
