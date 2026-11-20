// WEB paneli: geniş ekran kabuğu: ana-ayrıntı, tablolar, kısayollar, derin bağlantı, sekme başlığı.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TextField, ThemeMode;
import 'package:xc_asistan/core/theme/theme_mode_provider.dart';

import '../helpers/app_harness.dart';

const _web = Size(1440, 900);
const _laptop = Size(1024, 768);
const _phone = Size(390, 844);

final _placeholder = find.byKey(const ValueKey('master-detail-placeholder'));
final _customerSearch = find.byWidgetPredicate(
  (w) =>
      w is TextField && w.decoration?.hintText == 'Ad, telefon veya bölge ara',
);
final _palette = find.byKey(const ValueKey('palette-input'));

Future<void> ctrlK(AppHandle h) async {
  await h.tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await h.tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await h.tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await h.settle(6);
}

void main() {
  group('ana-ayrıntı (>= 1200 dp)', () {
    testWidgets('müşteriler kökü: solda liste, sağda boş durum', (
      tester,
    ) async {
      final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
      await h.go('/customers');
      expect(_customerSearch, findsOneWidget);
      expect(_placeholder, findsOneWidget);
      expect(find.text('Bir müşteri seçin'), findsOneWidget);
    });

    testWidgets(
      'müşteri kartı: liste solda KALIR, ayrıntı sağda açılır; Esc kapatır',
      (tester) async {
        final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
        await h.go('/customers/05321112233');
        expect(
          _customerSearch,
          findsOneWidget,
          reason: 'liste bölmesi görünür',
        );
        expect(_placeholder, findsNothing);
        expect(
          find.text('Ödeme durumu'),
          findsOneWidget,
          reason: 'ayrıntı bölmesi',
        );
        // Listedeki başka bir müşteriye dokun: ayrıntı sağda değişir, liste yerinde.
        await tester.tap(find.text('Ali Çelik').first);
        await h.settle();
        expect(h.location, startsWith('/customers/'));
        expect(h.location, isNot('/customers/05321112233'));
        expect(_customerSearch, findsOneWidget);
        // Esc: ayrıntı kapanır (bölme boş duruma döner)
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await h.settle();
        expect(h.location, '/customers');
        expect(_placeholder, findsOneWidget);
      },
    );

    testWidgets(
      'işler: yalnız çekirdek yönlendirmeyle liste + teklif ayrıntısı',
      (tester) async {
        final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
        await h.go('/jobs');
        expect(find.text('Bir teklif ya da iş seçin'), findsOneWidget);
        await h.go('/jobs/offers/off-1');
        expect(_placeholder, findsNothing);
        expect(
          find.byType(TextField),
          findsWidgets,
        ); // liste aramasının TextField'ı
      },
    );

    testWidgets('randevular listesi de ana-ayrıntı', (tester) async {
      final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
      await h.go('/appointments');
      expect(find.text('Bir randevu seçin'), findsOneWidget);
    });

    testWidgets('1024 dp: ana-ayrıntı YOK (tek bölme, sol menü var)', (
      tester,
    ) async {
      final h = await pumpXcApp(tester, role: 'admin', logicalSize: _laptop);
      await h.go('/customers');
      expect(_placeholder, findsNothing);
      expect(find.byKey(const ValueKey('nav-customers')), findsOneWidget);
      await h.go('/customers/05321112233');
      expect(_customerSearch, findsNothing);
      expect(find.text('Ödeme durumu'), findsOneWidget);
    });

    testWidgets(
      'telefon (390 dp): kenar menüsü yok, alt çubuk var, düzen aynı',
      (tester) async {
        final h = await pumpXcApp(tester, role: 'admin', logicalSize: _phone);
        await h.go('/customers');
        expect(_placeholder, findsNothing);
        expect(find.byKey(const ValueKey('side-search')), findsNothing);
        expect(find.byKey(const ValueKey('nav-customers')), findsOneWidget);
      },
    );

    testWidgets(
      'pencere 1440 → 1024 → 1440 yeniden boyutlanınca durum korunur',
      (tester) async {
        final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
        await h.go('/customers/05321112233');
        tester.view.physicalSize = _laptop;
        await h.settle();
        expect(find.text('Ödeme durumu'), findsOneWidget);
        tester.view.physicalSize = _web;
        await h.settle();
        expect(h.location, '/customers/05321112233');
        expect(_customerSearch, findsOneWidget);
        expect(find.text('Ödeme durumu'), findsOneWidget);
      },
    );
  });

  group('tablolar (geniş ekran)', () {
    testWidgets('Para → Ödemeler tablo; telefonda kart', (tester) async {
      var h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
      await h.go('/finance');
      await tester.tap(find.text('Ödemeler'));
      await h.settle();
      expect(find.byKey(const Key('payments-table')), findsOneWidget);
      // sütun başlığı ile sıralama
      await tester.tap(find.byKey(const ValueKey('sort-Tutar')));
      await h.settle(4);
      expect(find.byKey(const ValueKey('row-0')), findsOneWidget);

      h = await pumpXcApp(tester, role: 'admin', logicalSize: _phone);
      await h.go('/finance');
      await tester.tap(find.text('Ödemeler'));
      await h.settle();
      expect(find.byKey(const Key('payments-table')), findsNothing);
    });

    testWidgets('Para → Giderler tablo', (tester) async {
      final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
      await h.go('/finance');
      await tester.tap(find.text('Giderler'));
      await h.settle();
      expect(find.byKey(const Key('expenses-table')), findsOneWidget);
    });

    testWidgets('Fatura/KDV → Faturalar tablo', (tester) async {
      final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
      await h.go('/invoices-vat');
      await h.settle(20);
      expect(find.byKey(const Key('invoices-table')), findsOneWidget);
    });

    testWidgets('Kullanıcılar tablo (yönetici)', (tester) async {
      final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
      await h.go('/users');
      expect(find.byKey(const Key('users-table')), findsOneWidget);
    });

    testWidgets('Bugün panosu geniş ekranda sütunlara bölünür (taşma yok)', (
      tester,
    ) async {
      final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
      await h.go('/today');
      expect(tester.takeException(), isNull);
      // Sayı kutuları üstte tam genişlik; "Asistan Özeti" kartları iki ayrı sütunda AYNI hizada.
      final cards = find.text('Asistan Özeti');
      expect(cards, findsAtLeastNWidgets(2));
      final a = tester.getTopLeft(cards.at(0));
      final b = tester.getTopLeft(cards.at(1));
      expect(a.dy, b.dy);
      expect(a.dx == b.dx, isFalse);
    });
  });

  group('klavye kısayolları', () {
    testWidgets(
      'Ctrl+K paleti açar; "rapor" + Enter Raporlar sayfasına gider',
      (tester) async {
        final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
        await ctrlK(h);
        expect(_palette, findsOneWidget);
        await tester.enterText(_palette, 'rapor');
        await h.settle(3);
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await h.settle();
        expect(h.location, '/reports');
        expect(_palette, findsNothing);
      },
    );

    testWidgets('"/" paleti açar; Esc kapatır', (tester) async {
      final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await h.settle(6);
      expect(_palette, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle(6);
      expect(_palette, findsNothing);
    });

    testWidgets('metin alanına yazarken "/" paleti AÇMAZ', (tester) async {
      final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
      await h.go('/customers');
      await tester.tap(_customerSearch);
      await h.settle(4);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await h.settle(4);
      expect(_palette, findsNothing);
    });

    testWidgets('kenar menüsündeki "Hızlı git" kutusu paleti açar', (
      tester,
    ) async {
      final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
      await tester.tap(find.byKey(const ValueKey('side-search')));
      await h.settle(6);
      expect(_palette, findsOneWidget);
    });

    testWidgets('kenar menüsü: koyu/açık tema düğmesi', (tester) async {
      final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
      expect(h.container.read(themeModeProvider), isNot(ThemeMode.dark));
      await tester.tap(find.byKey(const ValueKey('side-theme')));
      await h.settle(4);
      expect(h.container.read(themeModeProvider), ThemeMode.dark);
    });
  });

  group('derin bağlantı, oturum ve sekme başlığı', () {
    testWidgets('girişsiz derin bağlantı → giriş → aynı sayfaya dönüş', (
      tester,
    ) async {
      final h = await pumpXcApp(
        tester,
        initialLocation: '/customers/05321112233',
        logicalSize: _web,
      );
      expect(h.location, startsWith('/login'));
      expect(h.location, contains('from='));
      await tester.enterText(
        find.byKey(const ValueKey('login-email')),
        'admin@demo.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'demo1234',
      );
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await h.settle(30);
      expect(h.location, '/customers/05321112233');
    });

    testWidgets(
      'açık oturumla derin bağlantı doğrudan açılır (F5 benzeri soğuk açılış)',
      (tester) async {
        final h = await pumpXcApp(
          tester,
          role: 'admin',
          initialLocation: '/jobs/offers/off-1',
          logicalSize: _web,
        );
        expect(h.location, '/jobs/offers/off-1');
      },
    );

    testWidgets(
      'rolün erişemediği derin bağlantı Bugün\'e düşer (saha → /users)',
      (tester) async {
        final h = await pumpXcApp(
          tester,
          role: 'saha',
          initialLocation: '/users',
          logicalSize: _web,
        );
        expect(h.location, '/today');
      },
    );

    testWidgets('sekme başlığı sayfaya göre güncellenir', (tester) async {
      final labels = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
            labels.add((call.arguments as Map)['label'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final h = await pumpXcApp(tester, role: 'admin', logicalSize: _web);
      await h.go('/reports');
      await h.go('/customers/05321112233');
      expect(labels, contains('Raporlar · XC Asistan'));
      expect(labels.last, 'Müşteri kartı · XC Asistan');
    });
  });
}
