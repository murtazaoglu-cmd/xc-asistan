// Ayarlar / kullanıcı yönetimi veri erişimi. Uçlar (sözleşme §12, /mnt/user-data/outputs/mobile-api-contract.md):
//   GET /users (A,O)            POST /users (A,O)           DELETE /users/:id (A,O; kendini silemez 400)
//   PATCH /users/:id/password (A,O sıfırlama)               PATCH /users/me/password (herkes; yeni jeton döner)
//   PATCH /users/:id  → sunucuda HENÜZ YOK (rol/aktif/ad; bkz. docs/CORE-REQUESTS.md backend isteği).
// POST /auth/logout-all core/auth üzerinden çalışır (Ayarlar > Oturum).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/api/api_providers.dart';
import '../../../core/auth/auth_models.dart';
import '../../../core/util/json.dart';
import 'user_models.dart';

/// `PATCH /users/:id` (rol atama / aktif-pasif) sunucuda yoksa arayüz bu özelliği gizler.
/// Sunucu eklenince `--dart-define=USER_EDIT_API=true` ile açılır. DEMO'da açıktır.
const bool kUserEditApi = bool.fromEnvironment('USER_EDIT_API');

abstract class SettingsRepository {
  Future<List<ManagedUser>> listUsers();
  Future<ManagedUser> createUser(NewUserInput input);
  Future<void> deleteUser(String id);

  /// Başka kullanıcının şifresini sıfırlar (hedefin tüm oturumları kapanır).
  Future<void> resetPassword(String id, String newPassword);

  /// Kendi şifreni değiştirir; yanıttaki YENİ jetonu döner (eski jetonlar iptal olur).
  Future<TokenResult> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Rol / aktif / ad güncelleme (sunucu desteği gerekir; bkz. [kUserEditApi]).
  Future<ManagedUser> updateUser(String id, UserPatch patch);
}

class HttpSettingsRepository implements SettingsRepository {
  HttpSettingsRepository(this.api);
  final ApiClient api;

  @override
  Future<List<ManagedUser>> listUsers() async =>
      (await api.getList('/users')).map(ManagedUser.fromJson).toList();

  @override
  Future<ManagedUser> createUser(NewUserInput input) async =>
      ManagedUser.fromJson(
        asJsonMap(await api.post('/users', data: input.toJson())),
      );

  @override
  Future<void> deleteUser(String id) async {
    await api.delete('/users/$id');
  }

  @override
  Future<void> resetPassword(String id, String newPassword) async {
    await api.patch('/users/$id/password', data: {'new_password': newPassword});
  }

  @override
  Future<TokenResult> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = asJsonMap(
      await api.patch(
        '/users/me/password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      ),
    );
    final r = TokenResult.fromJson(res);
    if (r.token.isEmpty) {
      throw const AppException(
        AppErrorCode.unknown,
        AppException.unknownMessage,
      );
    }
    return r;
  }

  @override
  Future<ManagedUser> updateUser(String id, UserPatch patch) async =>
      ManagedUser.fromJson(
        asJsonMap(await api.patch('/users/$id', data: patch.toJson())),
      );
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => HttpSettingsRepository(ref.watch(apiClientProvider)),
);

/// Rol/aktif düzenleme açık mı (sunucu desteği + DEMO).
final userEditEnabledProvider = Provider<bool>(
  (ref) => kUserEditApi || ref.watch(appConfigProvider).demo,
);

final usersProvider = FutureProvider.autoDispose<List<ManagedUser>>(
  (ref) => ref.watch(settingsRepositoryProvider).listUsers(),
);

/// Kullanıcı hatası → nazik Türkçe mesaj.
abstract final class UserErrors {
  static String message(Object error, {String op = 'save'}) {
    if (error is! AppException) return AppException.unknownMessage;
    switch (error.code) {
      case AppErrorCode.forbidden:
        return 'Bu işlem için yetkiniz yok.';
      case AppErrorCode.conflict:
        return op == 'delete'
            ? 'Bu kullanıcı silinemiyor (ilişkili kayıtlar olabilir).'
            : 'Bu e-posta ile kayıtlı bir kullanıcı zaten var.';
      case AppErrorCode.notFound:
        return op == 'edit-unsupported'
            ? 'Sunucu bu işlemi henüz desteklemiyor.'
            : 'Kullanıcı bulunamadı. Silinmiş olabilir; listeyi yenileyin.';
      case AppErrorCode.rateLimit:
        return 'Çok fazla deneme yapıldı. Birkaç dakika sonra tekrar deneyin.';
      default:
        return error.message;
    }
  }
}
