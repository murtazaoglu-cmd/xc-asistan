// Kullanıcı yönetimi ekranları: gerçek uygulama + DEMO sahte API (rol, korumalar, onay, doğrulama).
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/auth/session.dart';
import 'package:xc_asistan/core/api/api_providers.dart';
import 'package:xc_asistan/core/storage/storage_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/app_harness.dart';

Finder _field(String key) => find.descendant(
  of: find.byKey(Key(key)),
  matching: find.byType(EditableText),
);

Future<void> _type(AppHandle h, String key, String text) async {
  await h.tester.ensureVisible(_field(key));
  await h.tester.enterText(_field(key), text);
  await h.tester.pump();
}

Future<void> _tap(AppHandle h, Finder f) async {
  await h.tester.ensureVisible(f);
  await h.tester.tap(f, warnIfMissed: false);
  await h.settle();
}

Future<AppHandle> _app(
  WidgetTester t, {
  required String role,
  String initialLocation = '/today',
}) => pumpXcApp(
  t,
  role: role,
  initialLocation: initialLocation,
  logicalSize: const Size(412, 2400),
);

void main() {
  group('Kullanıcılar listesi', () {
    testWidgets('admin: tüm kullanıcılar, kendisi "(Siz)", rol rozetleri', (
      t,
    ) async {
      await _app(t, role: 'admin', initialLocation: '/users');
      expect(find.text('Kullanıcılar'), findsWidgets);
      expect(find.text('Yönetici (Siz)'), findsOneWidget);
      expect(find.text('Saha Ekibi'), findsOneWidget);
      expect(find.text('Ortak Personeli'), findsOneWidget);
      expect(find.byKey(const Key('add-user')), findsOneWidget);
    });

    testWidgets('arama: ad/e-postaya göre süzer', (t) async {
      final h = await _app(t, role: 'admin', initialLocation: '/users');
      await t.enterText(find.byKey(const Key('users-search')), 'saha@');
      await h.settle();
      expect(find.text('Saha Ekibi'), findsOneWidget);
      expect(find.widgetWithText(Card, 'Muhasebe'), findsNothing);
    });

    testWidgets('ortak yalnız kendi ekibini görür', (t) async {
      await _app(t, role: 'ortak', initialLocation: '/users');
      expect(find.text('Ortak Personeli'), findsOneWidget);
      expect(find.text('Saha Ekibi'), findsNothing);
      expect(find.text('Yönetici'), findsNothing);
    });

    for (final role in ['muhasebe', 'personel', 'saha']) {
      testWidgets('$role: /users rotası engellenir (Bugün\'e yönlenir)', (
        t,
      ) async {
        final h = await _app(t, role: role, initialLocation: '/users');
        expect(h.location, isNot(startsWith('/users')));
        expect(find.byKey(const Key('add-user')), findsNothing);
      });
    }

    testWidgets('Daha fazla menüsü: Kullanıcılar yalnız admin/ortak için', (
      t,
    ) async {
      await _app(t, role: 'admin', initialLocation: '/more');
      expect(find.text('Kullanıcılar'), findsOneWidget);
      await _app(t, role: 'personel', initialLocation: '/more');
      expect(find.text('Kullanıcılar'), findsNothing);
    });
  });

  group('Korumalar ve onay', () {
    testWidgets('kendini silme: düğme pasif, neden yazıyor', (t) async {
      final h = await _app(t, role: 'admin', initialLocation: '/users');
      await _tap(h, find.text('Yönetici (Siz)'));
      expect(find.text('Kendi hesabınızı silemezsiniz.'), findsOneWidget);
      final tile = t.widget<ListTile>(find.byKey(const Key('action-delete')));
      expect(tile.enabled, isFalse);
      expect(
        find.text('Kendi hesabınızı pasifleştiremezsiniz.'),
        findsOneWidget,
      );
    });

    testWidgets('silme: onay diyaloğu; Vazgeç silmez, Sil siler', (t) async {
      final h = await _app(t, role: 'admin', initialLocation: '/users');
      await _tap(h, find.text('Saha Ekibi'));
      await _tap(h, find.byKey(const Key('action-delete')));
      expect(find.text('Saha Ekibi silinsin mi?'), findsOneWidget);
      await _tap(h, find.text('Vazgeç'));
      expect(find.text('Saha Ekibi'), findsOneWidget);

      await _tap(h, find.text('Saha Ekibi'));
      await _tap(h, find.byKey(const Key('action-delete')));
      await _tap(h, find.text('Sil'));
      expect(find.text('Saha Ekibi silindi.'), findsOneWidget);
      await h.settle(20);
      expect(find.widgetWithText(Card, 'Saha Ekibi'), findsNothing);
    });

    testWidgets(
      'şifre sıfırlama: zayıf şifre reddedilir, geçerli şifre kaydedilir',
      (t) async {
        final h = await _app(t, role: 'admin', initialLocation: '/users');
        await _tap(h, find.text('personel@demo.com'));
        await _tap(h, find.byKey(const Key('action-resetPassword')));
        await _type(h, 'reset-password', '12345678');
        await _type(h, 'reset-confirm', '12345678');
        await _tap(h, find.byKey(const Key('reset-submit')));
        expect(find.textContaining('çok yaygın'), findsOneWidget);

        await _type(h, 'reset-password', 'Yeni-Parola-8');
        await _type(h, 'reset-confirm', 'Farkli-Parola-9');
        await _tap(h, find.byKey(const Key('reset-submit')));
        expect(find.text('Şifreler aynı değil.'), findsOneWidget);

        await _type(h, 'reset-confirm', 'Yeni-Parola-8');
        await _tap(h, find.byKey(const Key('reset-submit')));
        expect(find.textContaining('şifre sıfırlandı'), findsOneWidget);
      },
    );

    testWidgets('DEMO: rol değiştir ve pasifleştir onay ister', (t) async {
      final h = await _app(t, role: 'admin', initialLocation: '/users');
      await _tap(h, find.text('Saha Ekibi'));
      await _tap(h, find.byKey(const Key('action-toggleActive')));
      expect(find.text('Saha Ekibi pasifleştirilsin mi?'), findsOneWidget);
      await _tap(h, find.text('Pasifleştir').last);
      await h.settle(20);
      expect(find.text('Pasif'), findsOneWidget);

      await _tap(h, find.text('Saha Ekibi'));
      await _tap(h, find.byKey(const Key('action-changeRole')));
      await _tap(h, find.byKey(const Key('pick-role-muhasebe')));
      expect(
        find.textContaining('Muhasebe olarak değişsin mi'),
        findsOneWidget,
      );
      await _tap(h, find.text('Değiştir'));
      await h.settle(20);
      expect(find.text('Rol güncellendi: Muhasebe.'), findsOneWidget);
    });
  });

  group('Yeni kullanıcı formu', () {
    testWidgets('boş gönderim: alan hataları + rol seçilmeli', (t) async {
      final h = await _app(t, role: 'admin', initialLocation: '/users/new');
      await _tap(h, find.text('Kullanıcıyı ekle'));
      expect(find.text('Adı girin.'), findsOneWidget);
      expect(find.text('E-posta adresini girin.'), findsOneWidget);
      expect(find.text('Şifreyi girin.'), findsOneWidget);
      expect(find.byKey(const Key('role-error')), findsOneWidget);
    });

    testWidgets('admin 5 rol görür; ortak yalnız personel + saha', (t) async {
      await _app(t, role: 'admin', initialLocation: '/users/new');
      for (final r in ['admin', 'muhasebe', 'ortak', 'personel', 'saha']) {
        expect(
          find.byKey(Key('role-$r'), skipOffstage: false),
          findsOneWidget,
          reason: r,
        );
      }
      await _app(t, role: 'ortak', initialLocation: '/users/new');
      expect(
        find.byKey(const Key('role-saha'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('role-personel'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('role-admin'), skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const Key('role-ortak'), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('geçerli form: kullanıcı eklenir ve listede görünür', (
      t,
    ) async {
      final h = await _app(t, role: 'admin', initialLocation: '/users/new');
      await _type(h, 'field-name', 'Zeynep Kaya');
      await _type(h, 'field-email', 'zeynep@firma.com');
      await _type(h, 'field-password', 'Gizli-Parola-7');
      await _type(h, 'field-confirm', 'Gizli-Parola-7');
      await _tap(h, find.byKey(const Key('role-saha')));
      await _tap(h, find.text('Kullanıcıyı ekle'));
      await h.settle(20);
      expect(h.location, '/users');
      expect(find.text('Zeynep Kaya'), findsOneWidget);
    });

    testWidgets('aynı e-posta: 409 alan hatası olarak gösterilir', (t) async {
      final h = await _app(t, role: 'admin', initialLocation: '/users/new');
      await _type(h, 'field-name', 'Çift Kayıt');
      await _type(h, 'field-email', 'saha@demo.com');
      await _type(h, 'field-password', 'Gizli-Parola-7');
      await _type(h, 'field-confirm', 'Gizli-Parola-7');
      await _tap(h, find.byKey(const Key('role-saha')));
      await _tap(h, find.text('Kullanıcıyı ekle'));
      expect(
        find.text('Bu e-posta ile kayıtlı bir kullanıcı zaten var.'),
        findsOneWidget,
      );
      expect(h.location, '/users/new');
    });

    testWidgets('DEMO: personel/saha için ortak firma bağlanır', (t) async {
      final h = await _app(t, role: 'admin', initialLocation: '/users/new');
      await _type(h, 'field-name', 'Firma Personeli');
      await _type(h, 'field-email', 'fp@firma.com');
      await _type(h, 'field-password', 'Gizli-Parola-7');
      await _type(h, 'field-confirm', 'Gizli-Parola-7');
      await _tap(h, find.byKey(const Key('role-personel')));
      await _tap(h, find.byKey(const Key('field-leader')));
      await _tap(h, find.text('Ortak Firma').last);
      await _tap(h, find.text('Kullanıcıyı ekle'));
      await h.settle(20);
      expect(find.text('Firma Personeli'), findsOneWidget);
    });
  });

  group('Şifre değiştirme', () {
    testWidgets('Ayarlar\'da düğme var ve ekranı açar', (t) async {
      final h = await _app(t, role: 'saha', initialLocation: '/settings');
      await _tap(h, find.byKey(const Key('change-password')));
      expect(h.location, '/settings/password');
    });

    testWidgets('doğrulama: aynı şifre ve uyuşmayan tekrar reddedilir', (
      t,
    ) async {
      final h = await _app(
        t,
        role: 'admin',
        initialLocation: '/settings/password',
      );
      await _type(h, 'field-current', 'Eski-Parola-1');
      await _type(h, 'field-new', 'Eski-Parola-1');
      await _type(h, 'field-confirm', 'baska');
      await _tap(h, find.text('Şifreyi değiştir').last);
      expect(
        find.text('Yeni şifre mevcut şifreyle aynı olamaz.'),
        findsOneWidget,
      );
      expect(find.text('Şifreler aynı değil.'), findsOneWidget);
    });

    testWidgets('yanlış mevcut şifre: sunucu hatası gösterilir, oturum sürer', (
      t,
    ) async {
      final h = await _app(
        t,
        role: 'admin',
        initialLocation: '/settings/password',
      );
      await _type(h, 'field-current', 'yanlis');
      await _type(h, 'field-new', 'Yeni-Parola-8');
      await _type(h, 'field-confirm', 'Yeni-Parola-8');
      await _tap(h, find.text('Şifreyi değiştir').last);
      expect(find.byKey(const Key('password-error')), findsOneWidget);
      expect(find.text('Mevcut şifre hatalı.'), findsOneWidget);
      expect(h.container.read(sessionProvider), isA<SessionAuthenticated>());
    });

    testWidgets('başarı: yeni jeton saklanır, oturum açık kalır', (t) async {
      final h = await _app(
        t,
        role: 'admin',
        initialLocation: '/settings/password',
      );
      await _type(h, 'field-current', 'Eski-Parola-1');
      await _type(h, 'field-new', 'Yeni-Parola-8');
      await _type(h, 'field-confirm', 'Yeni-Parola-8');
      await _tap(h, find.text('Şifreyi değiştir').last);
      await h.settle(20);
      expect(find.textContaining('Şifreniz değiştirildi'), findsOneWidget);
      expect(h.location, '/settings');
      expect(h.container.read(sessionProvider), isA<SessionAuthenticated>());
    });

    testWidgets(
      'adoptToken: jeton hem bellekte hem güvenli depoda güncellenir',
      (t) async {
        final h = await _app(t, role: 'admin');
        await h.container
            .read(sessionProvider.notifier)
            .adoptToken('yeni-jeton');
        expect(h.container.read(tokenHolderProvider).token, 'yeni-jeton');
        expect(
          await h.container.read(tokenStoreProvider).readToken(),
          'yeni-jeton',
        );
        // Boş jeton yok sayılır.
        await h.container.read(sessionProvider.notifier).adoptToken('');
        expect(h.container.read(tokenHolderProvider).token, 'yeni-jeton');
      },
    );
  });

  group('Oturum', () {
    testWidgets(
      '"Tüm cihazlardan çıkış" Ayarlar\'da var; onaylanınca girişe döner',
      (t) async {
        final h = await _app(t, role: 'admin', initialLocation: '/settings');
        final btn = find.text('Tüm cihazlardan çıkış');
        await t.ensureVisible(btn);
        await _tap(h, btn);
        expect(find.text('Tüm cihazlardan çıkış yapılsın mı?'), findsOneWidget);
        await _tap(h, find.text('Tümünden çık'));
        await h.settle(20);
        expect(
          h.container.read(sessionProvider),
          isA<SessionUnauthenticated>(),
        );
      },
    );

    testWidgets('Ayarlar: Yönetim kartı yalnız admin/ortak', (t) async {
      await _app(t, role: 'admin', initialLocation: '/settings');
      expect(find.byKey(const Key('open-users')), findsOneWidget);
      await _app(t, role: 'saha', initialLocation: '/settings');
      expect(find.byKey(const Key('open-users')), findsNothing);
    });
  });
}
