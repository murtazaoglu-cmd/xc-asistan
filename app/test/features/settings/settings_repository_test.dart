import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/features/settings/data/settings_repository.dart';
import 'package:xc_asistan/features/settings/data/user_models.dart';

import '../../helpers/fakes.dart';
import '../customers/harness.dart';

void main() {
  test('listUsers: GET /users satırları modele çevrilir', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, [
        {
          'id': '1',
          'name': 'Ali',
          'email': 'a@x.com',
          'role': 'admin',
          'created_at': '2026-01-02T10:00:00Z',
        },
        {'id': '2', 'name': 'Veli', 'email': 'v@x.com', 'role': 'saha'},
      ]),
    );
    final r = await HttpSettingsRepository(apiWith(a)).listUsers();
    expect(a.requests.single.method, 'GET');
    expect(a.requests.single.path, '/users');
    expect(r.map((e) => e.name), ['Ali', 'Veli']);
    expect(r.first.createdAt, isNotNull);
  });

  test('createUser: POST /users gövdesi sözleşmedeki alanlar', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(201, {
        'id': '9',
        'name': 'Zeynep',
        'email': 'z@x.com',
        'role': 'personel',
      }),
    );
    final u = await HttpSettingsRepository(apiWith(a)).createUser(
      const NewUserInput(
        name: 'Zeynep',
        email: 'Z@x.com',
        password: 'Gizli-Parola-7',
        role: UserRole.personel,
      ),
    );
    expect(a.requests.single.method, 'POST');
    expect(a.requests.single.path, '/users');
    expect(a.requests.single.data, {
      'name': 'Zeynep',
      'email': 'z@x.com',
      'password': 'Gizli-Parola-7',
      'role': 'personel',
    });
    expect(u.id, '9');
  });

  test('createUser: 409 → conflict, 403 → forbidden', () async {
    for (final c in [
      (409, AppErrorCode.conflict),
      (403, AppErrorCode.forbidden),
    ]) {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(c.$1, {'error': 'x'}),
      );
      await expectLater(
        HttpSettingsRepository(apiWith(a)).createUser(
          const NewUserInput(
            name: 'A',
            email: 'a@x.com',
            password: 'Gizli-Parola-7',
            role: UserRole.saha,
          ),
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', c.$2)),
      );
    }
  });

  test('deleteUser: DELETE /users/:id', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, {'message': 'ok'}),
    );
    await HttpSettingsRepository(apiWith(a)).deleteUser('abc');
    expect(a.requests.single.method, 'DELETE');
    expect(a.requests.single.path, '/users/abc');
  });

  test('deleteUser: kendini silme 400 → validation (mesaj korunur)', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(400, {'error': 'Kendinizi silemezsiniz.'}),
    );
    await expectLater(
      HttpSettingsRepository(apiWith(a)).deleteUser('me'),
      throwsA(
        isA<AppException>().having(
          (e) => e.message,
          'message',
          contains('silemezsiniz'),
        ),
      ),
    );
  });

  test('resetPassword: PATCH /users/:id/password {new_password}', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, {'message': 'ok'}),
    );
    await HttpSettingsRepository(apiWith(a))
        .resetPassword('u1', 'Yeni-Parola-8');
    expect(a.requests.single.method, 'PATCH');
    expect(a.requests.single.path, '/users/u1/password');
    expect(a.requests.single.data, {'new_password': 'Yeni-Parola-8'});
  });

  test('changeOwnPassword: gövde + yeni jeton döner', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, {
        'message': 'ok',
        'token': 'yeni-jeton',
        'tokenType': 'Bearer',
        'expiresAt': '2026-12-20T16:11:11.000Z',
        'user': {'id': '1', 'name': 'Ali', 'email': 'a@x.com', 'role': 'admin'},
      }),
    );
    final r = await HttpSettingsRepository(
      apiWith(a),
    ).changeOwnPassword(currentPassword: 'eski', newPassword: 'Yeni-Parola-8');
    expect(a.requests.single.path, '/users/me/password');
    expect(a.requests.single.data, {
      'current_password': 'eski',
      'new_password': 'Yeni-Parola-8',
    });
    expect(r.token, 'yeni-jeton');
    expect(r.user?.role, UserRole.admin);
  });

  test(
    'changeOwnPassword: yanıtta jeton yoksa hata (oturum bozulmaz)',
    () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(200, {'message': 'ok'}),
      );
      await expectLater(
        HttpSettingsRepository(apiWith(a))
            .changeOwnPassword(currentPassword: 'a', newPassword: 'b'),
        throwsA(isA<AppException>()),
      );
    },
  );

  test('changeOwnPassword: mevcut şifre yanlış 400 mesajı iletilir', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(400, {'error': 'Mevcut şifre hatalı.'}),
    );
    await expectLater(
      HttpSettingsRepository(apiWith(a))
          .changeOwnPassword(currentPassword: 'x', newPassword: 'y'),
      throwsA(
        isA<AppException>().having(
          (e) => e.message,
          'm',
          contains('Mevcut şifre'),
        ),
      ),
    );
  });

  test('updateUser: PATCH /users/:id yalnız verilen alanlar', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, {
        'id': 'u',
        'name': 'A',
        'role': 'muhasebe',
        'active': false,
      }),
    );
    final u = await HttpSettingsRepository(
      apiWith(a),
    ).updateUser('u', const UserPatch(role: UserRole.muhasebe, active: false));
    expect(a.requests.single.path, '/users/u');
    expect(a.requests.single.data, {'role': 'muhasebe', 'active': false});
    expect(u.active, isFalse);
  });

  test('UserErrors: nazik mesajlar', () {
    expect(UserErrors.message(ex(AppErrorCode.conflict)), contains('e-posta'));
    expect(
      UserErrors.message(ex(AppErrorCode.conflict), op: 'delete'),
      contains('silinemiyor'),
    );
    expect(
      UserErrors.message(ex(AppErrorCode.forbidden)),
      contains('yetkiniz'),
    );
    expect(UserErrors.message(ex(AppErrorCode.rateLimit)), contains('deneme'));
    expect(
      UserErrors.message(ex(AppErrorCode.notFound), op: 'edit-unsupported'),
      contains('desteklemiyor'),
    );
    expect(UserErrors.message(Exception('x')), AppException.unknownMessage);
  });
}
