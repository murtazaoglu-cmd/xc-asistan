import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xc_asistan/core/router/shell_scaffold.dart';
import 'package:xc_asistan/core/ui/breakpoints.dart';

import '../helpers/app_harness.dart';

Finder nav(String id) => find.byKey(ValueKey('nav-$id'));
Finder drawerItem(String id) => find.byKey(ValueKey('drawer-$id'));

Future<void> openDrawer(AppHandle h) async {
  await h.tester.tap(find.byTooltip('Menü'));
  await h.settle(10);
}

void main() {
  group('kabuk: rol bazlı menü', () {
    testWidgets(
      'admin: alt çubukta 5 sekme (ortada Asistan), çekmecede seyrek ekranlar',
      (tester) async {
        final h = await pumpXcApp(tester, role: 'admin');
        expect(h.location, '/today');
        for (final id in [
          'today',
          'jobs',
          'assistant',
          'customers',
          'finance',
        ]) {
          expect(nav(id), findsOneWidget, reason: id);
        }
        // Asistan ortada ve büyük
        final order = ['today', 'jobs', 'assistant', 'customers', 'finance'];
        final xs = order.map((id) => tester.getCenter(nav(id)).dx).toList();
        expect(xs, orderedEquals([...xs]..sort()));
        expect(
          tester.getSize(nav('assistant')).width,
          greaterThanOrEqualTo(64),
        );
        expect(tester.getSize(nav('today')).height, greaterThanOrEqualTo(48));
        // alt çubuk etiketleri
        expect(find.text('Bugün'), findsWidgets);
        expect(find.text('İşler'), findsOneWidget);
        expect(find.text('Müşteriler'), findsOneWidget);
        expect(find.text('Para'), findsOneWidget);

        await openDrawer(h);
        for (final id in [
          'appointments',
          'stock',
          'reports',
          'invoices',
          'settings',
          'logout',
        ]) {
          expect(drawerItem(id), findsOneWidget, reason: id);
        }
        expect(find.text('Fatura / KDV'), findsOneWidget);
      },
    );

    testWidgets(
      'saha: SADE kabuk: yalnız Bugün + Randevular, finans/müşteri/teklif yok',
      (tester) async {
        final h = await pumpXcApp(tester, role: 'saha');
        expect(nav('today'), findsOneWidget);
        expect(nav('appointments'), findsOneWidget);
        for (final id in ['jobs', 'assistant', 'customers', 'finance']) {
          expect(nav(id), findsNothing, reason: id);
        }
        await openDrawer(h);
        expect(drawerItem('settings'), findsOneWidget);
        for (final id in ['appointments', 'stock', 'reports', 'invoices']) {
          expect(drawerItem(id), findsNothing, reason: id);
        }
      },
    );

    testWidgets('saha yasak yola gidemez: /finance → /today', (tester) async {
      final h = await pumpXcApp(tester, role: 'saha');
      await h.go('/finance');
      expect(h.location, '/today');
      await h.go('/jobs/offers/off-1');
      expect(h.location, '/today');
      await h.go('/appointments');
      expect(h.location, '/appointments');
    });

    testWidgets('personel: Müşteriler sekmesi yok, Para var', (tester) async {
      final h = await pumpXcApp(tester, role: 'personel');
      expect(nav('customers'), findsNothing);
      expect(nav('finance'), findsOneWidget);
      expect(nav('jobs'), findsOneWidget);
      await openDrawer(h);
      expect(drawerItem('invoices'), findsNothing);
      expect(
        drawerItem('stock'),
        findsNothing,
      ); // personelde materials yetkisi yok
    });

    testWidgets('çekmeceden Ayarlar açılır, sürüm metni görünür', (
      tester,
    ) async {
      final h = await pumpXcApp(tester, role: 'admin');
      await openDrawer(h);
      await tester.tap(drawerItem('settings'));
      await h.settle(15);
      expect(h.location, '/settings');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('version-text')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('version-text')), findsOneWidget);
    });
  });

  group('geniş ekran (>= 900)', () {
    testWidgets('alt çubuk yerine sol kenar menüsü; menü düğmesi yok', (
      tester,
    ) async {
      final h = await pumpXcApp(tester, role: 'admin');
      tester.view.physicalSize = const Size(1500, 1000); // dpr 3 → 500 dp: dar
      tester.view.devicePixelRatio = 1;
      await h.settle(15);
      expect(find.byType(SideNav), findsOneWidget);
      expect(find.byType(AppBottomBar), findsNothing);
      expect(find.byTooltip('Menü'), findsNothing);
      for (final id in [
        'today',
        'jobs',
        'assistant',
        'customers',
        'finance',
        'appointments',
        'stock',
        'reports',
        'invoices',
        'settings',
      ]) {
        expect(nav(id), findsOneWidget, reason: id);
      }
      await tester.tap(nav('customers'));
      await h.settle();
      expect(h.location, '/customers');
    });

    testWidgets('saha geniş ekranda da sade menü', (tester) async {
      final h = await pumpXcApp(tester, role: 'saha');
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      await h.settle(15);
      expect(find.byType(SideNav), findsOneWidget);
      expect(nav('today'), findsOneWidget);
      expect(nav('appointments'), findsOneWidget);
      expect(nav('finance'), findsNothing);
    });

    test('Breakpoints eşiği 900', () {
      expect(Breakpoints.isWideWidth(899.9), isFalse);
      expect(Breakpoints.isWideWidth(900), isTrue);
    });
  });

  group('gezinme', () {
    testWidgets(
      'sekme durumu korunur: detaydayken başka sekmeye geçip dönünce detay yerinde',
      (tester) async {
        final h = await pumpXcApp(tester, role: 'admin');
        await h.go('/jobs/offers/off-1');
        expect(h.location, '/jobs/offers/off-1');
        expect(
          find.textContaining('Ayşe Yılmaz'),
          findsWidgets,
        ); // teklif detayı yüklendi
        await tester.tap(nav('customers'));
        await h.settle();
        expect(h.location, '/customers');
        await tester.tap(nav('jobs'));
        await h.settle();
        expect(h.location, '/jobs/offers/off-1'); // durum korundu
      },
    );

    testWidgets('Android geri tuşu: iç sayfa → sekme kökü → Bugün → çıkış', (
      tester,
    ) async {
      final h = await pumpXcApp(tester, role: 'admin');
      await h.go('/jobs');
      await h.go('/jobs/offers/off-1');
      expect(await tester.binding.handlePopRoute(), isTrue); // detaydan listeye
      await h.settle();
      expect(h.location, '/jobs');
      expect(
        await tester.binding.handlePopRoute(),
        isTrue,
      ); // sekme kökünden Bugün'e
      await h.settle();
      expect(h.location, '/today');
      // Bugün kökünde sistem geri tuşunu uygulamaya bırakır (çıkış): işlenmez.
      expect(await tester.binding.handlePopRoute(), isFalse);
    });

    testWidgets('seyrek ekrandan geri → Bugün', (tester) async {
      final h = await pumpXcApp(tester, role: 'admin');
      await h.go('/stock');
      expect(h.location, '/stock');
      expect(await tester.binding.handlePopRoute(), isTrue);
      await h.settle();
      expect(h.location, '/today');
    });

    testWidgets('derin bağlantı rotaları: teklif, proje, müşteri, randevu', (
      tester,
    ) async {
      final h = await pumpXcApp(tester, role: 'admin');
      for (final p in [
        '/jobs/offers/off-1',
        '/jobs/projects/prj-2',
        '/customers/05321112233',
        '/appointments/apt-1',
        '/assistant/share',
      ]) {
        await h.go(p);
        expect(h.location, p);
      }
    });

    testWidgets('Bugün ekranı demo veriyle yüklenir (referans ekran)', (
      tester,
    ) async {
      await pumpXcApp(tester, role: 'admin');
      // Selamlama saate göre değişir (Günaydın / İyi günler / İyi akşamlar / İyi geceler).
      expect(
        find.textContaining(
          RegExp(r'(Günaydın|İyi günler|İyi akşamlar|İyi geceler), Yönetici'),
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.textContaining('Ayşe Yılmaz'), 300);
      expect(find.textContaining('Ayşe Yılmaz'), findsWidgets);
    });

    testWidgets('saha Bugün ekranında finans/teklif bölümü yok', (
      tester,
    ) async {
      await pumpXcApp(tester, role: 'saha');
      expect(find.textContaining('Merhaba, Saha Ekibi'), findsOneWidget);
      expect(find.text('Dikkat gerektirenler'), findsNothing);
      expect(find.text('Para'), findsNothing);
    });
  });

  group('giriş akışı', () {
    testWidgets('girişsiz açılış → /login; giriş → /today; çıkış → /login', (
      tester,
    ) async {
      final h = await pumpXcApp(tester);
      expect(h.location.startsWith('/login'), isTrue);
      expect(find.byKey(const ValueKey('login-submit')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('login-email')),
        'muhasebe@demo.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'sifre123',
      );
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await h.settle(25);
      expect(h.location, '/today');
      expect(nav('finance'), findsOneWidget);
      await openDrawer(h);
      await tester.tap(drawerItem('logout'));
      await h.settle(10);
      await tester.tap(find.text('Çıkış yap').last);
      await h.settle(25);
      expect(h.location.startsWith('/login'), isTrue);
    });

    testWidgets('boş alan ve hatalı şifre mesajları', (tester) async {
      final h = await pumpXcApp(tester);
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await h.settle();
      expect(find.text('E-posta adresinizi girin.'), findsOneWidget);
      expect(find.text('Şifrenizi girin.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('login-email')),
        'a@demo.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'yanlis',
      );
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await h.settle(25);
      expect(find.text('E-posta veya şifre hatalı.'), findsOneWidget);
      expect(h.location.startsWith('/login'), isTrue);
    });

    testWidgets('derin bağlantı girişten sonra korunur', (tester) async {
      final h = await pumpXcApp(tester, initialLocation: '/jobs/offers/off-1');
      expect(h.location, startsWith('/login?from='));
      await tester.enterText(
        find.byKey(const ValueKey('login-email')),
        'admin@demo.com',
      );
      await tester.enterText(find.byKey(const ValueKey('login-password')), 'x');
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await h.settle(25);
      expect(h.location, '/jobs/offers/off-1');
    });
  });
}
