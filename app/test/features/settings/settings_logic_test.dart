import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/router/nav_items.dart';
import 'package:xc_asistan/core/router/routes.dart';
import 'package:xc_asistan/core/config/brand_profile.dart';
import 'package:xc_asistan/features/settings/data/user_models.dart';
import 'package:xc_asistan/features/settings/data/user_rules.dart';

ManagedUser u(String id, UserRole r, {bool active = true}) => ManagedUser(
  id: id,
  name: 'K $id',
  email: '$id@x.com',
  roleRaw: r.api,
  active: active,
);

void main() {
  group('ManagedUser', () {
    test('fromJson: eksik alanda çökmez, aktif varsayılır', () {
      final m = ManagedUser.fromJson({
        'id': 'a',
        'name': 'Ayşe',
        'role': 'saha',
      });
      expect(m.role, UserRole.saha);
      expect(m.active, isTrue);
      expect(m.createdAt, isNull);
      expect(m.initial, 'A');
    });
    test('bilinmeyen rol olduğu gibi gösterilir, yönetici sayılmaz', () {
      final m = ManagedUser.fromJson({
        'id': 'a',
        'name': '',
        'role': 'misafir',
      });
      expect(m.role, isNull);
      expect(m.roleLabel, 'misafir');
      expect(m.isAdmin, isFalse);
      expect(m.initial, '?');
    });
    test('active=false okunur', () {
      expect(
        ManagedUser.fromJson({'id': 'a', 'active': false}).active,
        isFalse,
      );
    });
  });

  group('NewUserInput / UserPatch', () {
    test('e-posta küçük harf + kırpılır; leader_id yalnız doluysa', () {
      final a = const NewUserInput(
        name: ' Ali ',
        email: ' ALI@Firma.com ',
        password: 'abcd1234',
        role: UserRole.saha,
      ).toJson();
      expect(a, {
        'name': 'Ali',
        'email': 'ali@firma.com',
        'password': 'abcd1234',
        'role': 'saha',
      });
      final b = const NewUserInput(
        name: 'Ali',
        email: 'a@b.co',
        password: 'abcd1234',
        role: UserRole.personel,
        leaderId: 'o1',
      ).toJson();
      expect(b['leader_id'], 'o1');
    });
    test('UserPatch yalnız verilen alanları gönderir', () {
      expect(const UserPatch(active: false).toJson(), {'active': false});
      expect(const UserPatch(role: UserRole.muhasebe).toJson(), {
        'role': 'muhasebe',
      });
    });
  });

  group('UserRules', () {
    test('yalnız admin/ortak yönetir', () {
      expect(UserRules.canManage(UserRole.admin), isTrue);
      expect(UserRules.canManage(UserRole.ortak), isTrue);
      for (final r in [UserRole.muhasebe, UserRole.personel, UserRole.saha]) {
        expect(UserRules.canManage(r), isFalse);
        expect(UserRules.assignableRoles(r), isEmpty);
      }
    });
    test('atanabilir roller: admin 5, ortak yalnız personel+saha', () {
      expect(UserRules.assignableRoles(UserRole.admin), hasLength(5));
      expect(UserRules.assignableRoles(UserRole.ortak), [
        UserRole.personel,
        UserRole.saha,
      ]);
    });
    test('silme: kendini silemez', () {
      final me = u('me', UserRole.admin);
      final all = [me, u('b', UserRole.admin)];
      expect(
        UserRules.deleteBlock(
          actor: UserRole.admin,
          selfId: 'me',
          target: me,
          all: all,
        ),
        contains('Kendi hesabınızı'),
      );
    });
    test('silme: son admin korunur, başka admin varsa silinebilir', () {
      final only = u('a', UserRole.admin);
      expect(
        UserRules.deleteBlock(
          actor: UserRole.admin,
          selfId: 'x',
          target: only,
          all: [only, u('s', UserRole.saha)],
        ),
        contains('Son yönetici'),
      );
      final two = [only, u('b', UserRole.admin)];
      expect(
        UserRules.deleteBlock(
          actor: UserRole.admin,
          selfId: 'x',
          target: only,
          all: two,
        ),
        isNull,
      );
    });
    test('silme: ortak yalnız personel/saha siler; yetkisiz rol silemez', () {
      final p = u('p', UserRole.personel);
      final o = u('o', UserRole.ortak);
      expect(
        UserRules.deleteBlock(
          actor: UserRole.ortak,
          selfId: 'x',
          target: p,
          all: [p],
        ),
        isNull,
      );
      expect(
        UserRules.deleteBlock(
          actor: UserRole.ortak,
          selfId: 'x',
          target: o,
          all: [o],
        ),
        isNotNull,
      );
      expect(
        UserRules.deleteBlock(
          actor: UserRole.personel,
          selfId: 'x',
          target: p,
          all: [p],
        ),
        isNotNull,
      );
    });
    test('şifre sıfırlama: kendin için yönlendirme mesajı; ortak kapsamı', () {
      final me = u('me', UserRole.admin);
      expect(
        UserRules.resetBlock(actor: UserRole.admin, selfId: 'me', target: me),
        contains('Şifremi değiştir'),
      );
      expect(
        UserRules.resetBlock(
          actor: UserRole.admin,
          selfId: 'me',
          target: u('b', UserRole.saha),
        ),
        isNull,
      );
      expect(
        UserRules.resetBlock(
          actor: UserRole.ortak,
          selfId: 'me',
          target: u('m', UserRole.muhasebe),
        ),
        isNotNull,
      );
    });
    test('rol değiştirme: yalnız admin, kendi rolü ve son admin korunur', () {
      final a = u('a', UserRole.admin);
      final all = [a, u('s', UserRole.saha)];
      expect(
        UserRules.roleChangeBlock(
          actor: UserRole.ortak,
          selfId: 'x',
          target: all[1],
          all: all,
        ),
        isNotNull,
      );
      expect(
        UserRules.roleChangeBlock(
          actor: UserRole.admin,
          selfId: 'a',
          target: a,
          all: all,
        ),
        contains('Kendi rolünüzü'),
      );
      expect(
        UserRules.roleChangeBlock(
          actor: UserRole.admin,
          selfId: 'z',
          target: a,
          all: all,
        ),
        contains('Son yönetici'),
      );
      expect(
        UserRules.roleChangeBlock(
          actor: UserRole.admin,
          selfId: 'a',
          target: all[1],
          all: all,
        ),
        isNull,
      );
    });
    test('pasifleştirme: son aktif admin ve kendin korunur; pasifi aktifleştirmek serbest', () {
      final a = u('a', UserRole.admin);
      final b = u('b', UserRole.admin, active: false);
      final all = [a, b];
      expect(
        UserRules.activeToggleBlock(
          actor: UserRole.admin,
          selfId: 'z',
          target: a,
          all: all,
        ),
        contains('Son aktif'),
      );
      expect(
        UserRules.activeToggleBlock(
          actor: UserRole.admin,
          selfId: 'z',
          target: b,
          all: all,
        ),
        isNull,
      );
      expect(
        UserRules.activeToggleBlock(
          actor: UserRole.admin,
          selfId: 'a',
          target: a,
          all: all,
        ),
        contains('Kendi hesabınızı'),
      );
    });
  });

  group('UserValidators', () {
    test('ad', () {
      expect(UserValidators.name(' '), isNotNull);
      expect(UserValidators.name('a' * 101), isNotNull);
      expect(UserValidators.name('Ali'), isNull);
    });
    test('e-posta', () {
      for (final bad in ['', 'ali', 'ali@', 'ali@x', 'a li@x.com', '@x.com']) {
        expect(UserValidators.email(bad), isNotNull, reason: bad);
      }
      expect(UserValidators.email('ali@firma.com.tr'), isNull);
    });
    test('şifre: en az 8, en çok 72 bayt, yaygın şifre reddedilir', () {
      expect(UserValidators.password(''), isNotNull);
      expect(UserValidators.password('abc123'), contains('en az 8'));
      expect(UserValidators.password('12345678'), contains('yaygın'));
      expect(UserValidators.password('PassWord1'), contains('yaygın'));
      expect(UserValidators.password('ş' * 40), contains('uzun')); // 80 bayt
      expect(UserValidators.password('Gizli-Parola-7'), isNull);
    });
    test('tekrar ve yeni şifre', () {
      expect(UserValidators.confirm('', 'abc'), isNotNull);
      expect(UserValidators.confirm('x', 'y'), contains('aynı değil'));
      expect(UserValidators.confirm('y', 'y'), isNull);
      expect(
        UserValidators.newPassword('Gizli-Parola-7', 'Gizli-Parola-7'),
        contains('aynı olamaz'),
      );
      expect(
        UserValidators.newPassword('Yeni-Parola-8', 'Gizli-Parola-7'),
        isNull,
      );
      expect(UserValidators.currentPassword(''), isNotNull);
    });
    test('rol: seçilmeli ve atanabilir olmalı', () {
      expect(UserValidators.role(null, UserRole.admin), isNotNull);
      expect(UserValidators.role(UserRole.admin, UserRole.ortak), isNotNull);
      expect(UserValidators.role(UserRole.saha, UserRole.ortak), isNull);
    });
  });

  group('menü ve rota görünürlüğü', () {
    const g = Glossary();
    List<String> ids(UserRole r) => NavCatalog.drawer(
      AppCapabilities.forRole(r),
      g,
    ).map((e) => e.id).toList();

    test('Kullanıcılar menüsü yalnız admin ve ortak', () {
      expect(ids(UserRole.admin), contains('users'));
      expect(ids(UserRole.ortak), contains('users'));
      for (final r in [UserRole.muhasebe, UserRole.personel, UserRole.saha]) {
        expect(ids(r), isNot(contains('users')), reason: r.api);
      }
    });
    test('RouteGuard /users: admin/ortak evet; diğerleri hayır', () {
      for (final r in UserRole.values) {
        final ok = r == UserRole.admin || r == UserRole.ortak;
        expect(
          RouteGuard.isAllowed(Routes.users, AppCapabilities.forRole(r)),
          ok,
          reason: r.api,
        );
        expect(
          RouteGuard.isAllowed(
            '${Routes.users}/new',
            AppCapabilities.forRole(r),
          ),
          ok,
        );
      }
    });
    test('sunucu manageUsers=false derse admin bile menüde görmez', () {
      final caps = AppCapabilities.fromJson({
        'manageUsers': false,
        'offers': true,
      }, UserRole.admin);
      expect(caps.showUsers, isFalse);
    });
    test('Şifre değiştirme rotası herkese açık (ayarlar altında)', () {
      for (final r in UserRole.values) {
        expect(
          RouteGuard.isAllowed(
            Routes.changePassword,
            AppCapabilities.forRole(r),
          ),
          isTrue,
        );
      }
    });
  });
}
