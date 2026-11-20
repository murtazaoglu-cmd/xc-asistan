// Modüller arası bağlantılar (lib/app_wiring.dart, rota koruması, menü, çekirdek eklemeleri).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Icons, Scrollable;
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/config/brand_profile.dart';
import 'package:xc_asistan/core/router/nav_items.dart';
import 'package:xc_asistan/core/router/routes.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/finance/data/finance_input.dart';
import 'package:xc_asistan/features/finance/data/finance_models.dart';

import '../helpers/app_harness.dart';

void main() {
  group('saha rotaları', () {
    final caps = AppCapabilities.forRole(UserRole.saha);
    test('sade brifing, gün sonu, gelen kutusu, tercihler açık', () {
      for (final p in [
        '/assistant/briefing',
        '/assistant/briefing/history',
        '/assistant/closure',
        '/assistant/inbox',
        '/assistant/prefs',
      ]) {
        expect(RouteGuard.isAllowed(p, caps), isTrue, reason: p);
      }
    });
    test('sohbet, içe aktarma, içgörü, öneri kapalı', () {
      for (final p in [
        '/assistant',
        '/assistant/share',
        '/assistant/insights',
        '/assistant/suggestions',
        '/assistant/consents',
        '/finance',
      ]) {
        expect(RouteGuard.isAllowed(p, caps), isFalse, reason: p);
      }
    });
  });

  group('menü', () {
    const g = Glossary();
    test('yönetici menüsü: Müşteriler ve Asistan da bulunur', () {
      final ids = NavCatalog.drawer(
        AppCapabilities.forRole(UserRole.admin),
        g,
      ).map((e) => e.id);
      expect(
        ids,
        containsAll([
          'customers',
          'assistant',
          'appointments',
          'stock',
          'reports',
          'invoices',
          'settings',
        ]),
      );
    });
    test('saha menüsü yalnız Ayarlar (finans/müşteri yok)', () {
      final ids = NavCatalog.drawer(
        AppCapabilities.forRole(UserRole.saha),
        g,
      ).map((e) => e.id);
      expect(ids, ['settings']);
    });
  });

  group('çekirdek eklemeleri', () {
    test('Glossary.expenseCategories fromJson ve öncelik sırası', () {
      final t = Glossary.fromJson({
        'expenseCategories': ['Boya', 'Fayans'],
        'expenseCategoryLabels': {'Malzeme': 'Malzeme'},
      });
      expect(t.expenseCategories, ['Boya', 'Fayans']);
      final opts = FinanceCategories.options(
        t,
        scope: ScopeView.business,
        hasProject: false,
      );
      expect(opts.take(2), ['Boya', 'Fayans']);
      expect(const Glossary().expenseCategories, isEmpty);
    });

    test('ProjectRef: sunucu balance (ilave işler dahil) kullanılır', () {
      final p = ProjectRef.fromJson({
        'id': 'p1',
        'customer_name': 'A',
        'customer_phone': '0532 111 22 33',
        'total_amount': 1000,
        'paid_amount': 400,
        'balance': 850,
      });
      expect(p.customerPhone, '0532 111 22 33');
      expect(p.remaining, Money.fromKurus(85000));
      // elle paid/extras değişince sunucu bakiyesi eskimiş sayılır
      expect(p.copyWith(paid: Money.fromKurus(100000)).remaining, Money.zero);
      // balance yoksa eski hesap
      final q = ProjectRef.fromJson({
        'id': 'p2',
        'customer_name': 'B',
        'total_amount': 1000,
        'paid_amount': 400,
      });
      expect(q.remaining, Money.fromKurus(60000));
    });
  });

  group('uygulama (DEMO)', () {
    testWidgets('Ayarlar: asistan bildirim tercihleri gömülü', (t) async {
      final h = await pumpXcApp(t, role: 'admin', initialLocation: '/settings');
      await h.settle(20);
      await t.scrollUntilVisible(
        find.text('Asistan bildirimleri'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Asistan bildirimleri'), findsOneWidget);
    });

    testWidgets('Bugün: asistan özeti ve zil', (t) async {
      final h = await pumpXcApp(t, role: 'admin');
      await h.settle(20);
      expect(find.text('Asistan Özeti'), findsWidgets);
      expect(find.byIcon(Icons.notifications_none), findsWidgets);
    });

    testWidgets('Fatura/KDV DEMO uçları kayıtlı', (t) async {
      final h = await pumpXcApp(
        t,
        role: 'admin',
        initialLocation: '/invoices-vat',
      );
      await h.settle(20);
      expect(find.textContaining('bulunamadı'), findsNothing);
      expect(h.location, '/invoices-vat');
    });
  });
}
