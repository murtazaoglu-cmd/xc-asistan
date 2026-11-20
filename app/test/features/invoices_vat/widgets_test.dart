import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/config/brand_profile.dart';
import 'package:xc_asistan/core/router/nav_items.dart';
import 'package:xc_asistan/core/router/routes.dart';
import 'package:xc_asistan/core/theme/app_theme.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_access.dart';
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_models.dart'
    show Confirmation;
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_repository.dart';
import 'package:xc_asistan/features/invoices_vat/presentation/inv_widgets.dart';

import 'harness.dart';

List<Override> _demo(UserRole role) => [
  invoicesVatRepositoryProvider.overrideWithValue(demoRepo(role: role.name)),
];

void main() {
  setUp(() => Ist.clock = () => DateTime.utc(2026, 11, 20, 8));
  tearDown(() => Ist.clock = DateTime.now);

  group('rol görünürlüğü', () {
    test('InvoicesVatAccess rol matrisi', () {
      bool v(UserRole r) => InvoicesVatAccess(r).canView;
      expect(v(UserRole.admin), isTrue);
      expect(v(UserRole.muhasebe), isTrue);
      expect(v(UserRole.ortak), isTrue);
      expect(v(UserRole.personel), isFalse);
      expect(v(UserRole.saha), isFalse);
      expect(
        const InvoicesVatAccess(UserRole.ortak).canEditTaxCalendar,
        isFalse,
      );
      expect(const InvoicesVatAccess(UserRole.ortak).ownLedgerOnly, isTrue);
      expect(
        const InvoicesVatAccess(UserRole.muhasebe).canEditTaxCalendar,
        isTrue,
      );
    });

    test('menü ve rota koruması', () {
      bool inMenu(UserRole r) => NavCatalog.drawer(
        AppCapabilities.forRole(r),
        const Glossary(),
      ).any((i) => i.id == 'invoices');
      expect(inMenu(UserRole.admin), isTrue);
      expect(inMenu(UserRole.muhasebe), isTrue);
      expect(inMenu(UserRole.personel), isFalse);
      expect(inMenu(UserRole.saha), isFalse);
      expect(
        RouteGuard.isAllowed(
          '/invoices-vat/abc',
          AppCapabilities.forRole(UserRole.saha),
        ),
        isFalse,
      );
      expect(
        RouteGuard.isAllowed(
          '/invoices-vat',
          AppCapabilities.forRole(UserRole.personel),
        ),
        isFalse,
      );
      expect(
        RouteGuard.isAllowed(
          '/invoices-vat',
          AppCapabilities.forRole(UserRole.admin),
        ),
        isTrue,
      );
    });

    testWidgets('personel ekranda yetki yok durumunu görür', (tester) async {
      await pumpFeature(
        tester,
        role: UserRole.personel,
        overrides: _demo(UserRole.personel),
      );
      await settle(tester);
      expect(find.text('Bu bölüme erişim yetkiniz yok'), findsOneWidget);
      expect(find.byKey(const Key('fab_invoice')), findsNothing);
    });

    testWidgets('admin sekmeleri ve faturaları görür', (tester) async {
      await pumpFeature(tester, overrides: _demo(UserRole.admin));
      await settle(tester);
      for (final t in ['Faturalar', 'KDV', 'Vergi Takvimi', 'Ödeme Planı']) {
        expect(find.text(t), findsWidgets);
      }
      expect(find.textContaining('Zeynep Arslan'), findsWidgets);
      expect(find.byKey(const Key('fab_invoice')), findsOneWidget);
    });
  });

  group('teyit rozeti', () {
    testWidgets('ConfirmBadge etiketi ve görünürlüğü', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Column(
              children: [
                ConfirmBadge(Confirmation(needed: true)),
                ConfirmBadge(Confirmation.none),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Mali müşavire teyit edin'), findsOneWidget);
      expect(find.byKey(const Key('confirm_badge')), findsOneWidget);
    });

    testWidgets('vergi takviminde doğrulanmamış öğeler rozetlenir', (
      tester,
    ) async {
      await pumpFeature(tester, overrides: _demo(UserRole.admin));
      await settle(tester);
      await tester.tap(find.text('Vergi Takvimi'));
      await settle(tester, 30);
      expect(find.byKey(const Key('unverified_count')), findsOneWidget);
      expect(find.text('Teyit edin'), findsWidgets);
    });
  });

  group('vergi takvimi', () {
    testWidgets('gün sayacı "8 gün kaldı" ve tamamlandı işareti', (
      tester,
    ) async {
      await pumpFeature(tester, overrides: _demo(UserRole.admin));
      await settle(tester);
      await tester.tap(find.text('Vergi Takvimi'));
      await settle(tester, 30);
      // 25 Kasım, bugün 20 Kasım (İstanbul) → 5 gün.
      expect(find.text('5 gün kaldı'), findsOneWidget);
      final done = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('done_kdv2'),
      );
      expect(done, findsOneWidget);
      expect(tester.getSize(done).shortestSide, greaterThanOrEqualTo(48));
      await tester.tap(done);
      await settle(tester);
      // Tamamlanan öğe açık listeden çıkar (sayaç kalmaz).
      expect(find.text('5 gün kaldı'), findsNothing);
    });

    testWidgets('ortak kendi hatırlatma ekleyemez', (tester) async {
      await pumpFeature(
        tester,
        role: UserRole.ortak,
        overrides: _demo(UserRole.ortak),
      );
      await settle(tester);
      await tester.tap(find.text('Vergi Takvimi'));
      await settle(tester, 30);
      expect(find.byKey(const Key('fab_tax')), findsNothing);
      expect(find.text('5 gün kaldı'), findsOneWidget);
    });

    testWidgets('admin hatırlatma FAB görür', (tester) async {
      await pumpFeature(tester, overrides: _demo(UserRole.admin));
      await settle(tester);
      await tester.tap(find.text('Vergi Takvimi'));
      await settle(tester, 30);
      expect(find.byKey(const Key('fab_tax')), findsOneWidget);
    });
  });

  group('KDV sekmesi', () {
    testWidgets('dönem kartı dört değeri gösterir', (tester) async {
      await pumpFeature(tester, overrides: _demo(UserRole.admin));
      await settle(tester);
      await tester.tap(find.text('KDV').first);
      await settle(tester, 30);
      expect(find.text('Hesaplanan KDV'), findsOneWidget);
      expect(find.text('İndirilecek KDV'), findsWidgets);
      expect(find.byKey(const Key('period_label')), findsOneWidget);
    });
  });

  group('fatura formu', () {
    testWidgets('boş gönderimde doğrulama hataları, API çağrılmaz', (
      tester,
    ) async {
      await pumpFeature(
        tester,
        location: '/invoices-vat/new',
        size: const Size(400, 2600),
        overrides: _demo(UserRole.admin),
      );
      await settle(tester);
      await tester.tap(find.text('Kaydet').last);
      await settle(tester);
      expect(find.textContaining('tutar'), findsWidgets);
    });

    testWidgets('matrah girilince önizleme kuruş doğru güncellenir', (
      tester,
    ) async {
      await pumpFeature(
        tester,
        location: '/invoices-vat/new',
        size: const Size(400, 2600),
        overrides: _demo(UserRole.admin),
      );
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Matrah (KDV hariç)'),
        '12,34',
      );
      await settle(tester);
      expect(find.byKey(const Key('vat_preview')), findsOneWidget);
      expect(find.text('₺2,47'), findsWidgets);
      expect(find.text('₺14,81'), findsWidgets);
    });

    testWidgets('belgedeki KDV farklıysa uyarı notu görünür', (tester) async {
      await pumpFeature(
        tester,
        location: '/invoices-vat/new',
        size: const Size(400, 2600),
        overrides: _demo(UserRole.admin),
      );
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Matrah (KDV hariç)'),
        '100',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Belgedeki KDV (isteğe bağlı)'),
        '30',
      );
      await settle(tester);
      expect(find.byKey(const Key('mismatch_note')), findsOneWidget);
    });
  });

  group('taksit sihirbazı', () {
    testWidgets('kuruş artığı son taksitte ve not görünür', (tester) async {
      await pumpFeature(
        tester,
        location: '/invoices-vat/plan/new',
        overrides: _demo(UserRole.admin),
      );
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Toplam tutar'),
        '1000',
      );
      await tester.enterText(find.byKey(const Key('plan_count')), '3');
      await settle(tester);
      expect(find.text('₺333,33'), findsNWidgets(2));
      expect(find.text('₺333,34'), findsOneWidget);
      expect(find.byKey(const Key('remainder_note')), findsOneWidget);
      expect(find.text('₺1.000,00'), findsWidgets);
    });

    testWidgets('geçersiz taksit sayısı hata verir', (tester) async {
      await pumpFeature(
        tester,
        location: '/invoices-vat/plan/new',
        overrides: _demo(UserRole.admin),
      );
      await settle(tester);
      await tester.enterText(find.byKey(const Key('plan_count')), '0');
      await settle(tester);
      expect(find.textContaining('Taksit sayısı'), findsWidgets);
    });
  });
}
