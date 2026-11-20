import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/theme/app_theme.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/finance/data/finance_calc.dart';
import 'package:xc_asistan/features/finance/data/finance_providers.dart';
import 'package:xc_asistan/features/finance/presentation/finance_chart.dart';

import 'finance_harness.dart';

Finder inCard(String key, Finder f) =>
    find.descendant(of: find.byKey(Key(key)), matching: f);

void main() {
  setUp(() => Ist.clock = () => DateTime.utc(2026, 11, 20, 8));
  tearDown(() => Ist.clock = DateTime.now);

  group('Grafik', () {
    List<ChartMonth> months() =>
        FinanceCalc.chartWindow(const [], const [], const YearMonth(2026, 11));

    test('eksen adımı güzel sayılara yuvarlanır', () {
      expect(niceAxisStep(0), 1);
      expect(niceAxisStep(100), 25);
      expect(niceAxisStep(19050), 5000);
      expect(niceAxisStep(7), 2);
      expect(niceAxisStep(1200000), 500000);
    });

    testWidgets('6 ay, ay başına 2 çubuk (gelir/gider), seçili ay kartı', (
      tester,
    ) async {
      final m = [
        for (final c in months())
          ChartMonth(
            month: c.month,
            revenue: c.month.month == 11 ? Money.fromTl(12500) : Money.zero,
            expense: c.month.month == 11 ? Money.fromTl(19050.5) : Money.zero,
            hasData: c.month.month == 11,
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: FinanceChart(months: m)),
          ),
        ),
      );
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups.length, 6);
      expect(chart.data.barGroups.every((g) => g.barRods.length == 2), isTrue);
      // Eksen etiketleri kısa; seçili (son) ay kartı büyük yazıyla.
      expect(find.text('Kas 2026'), findsOneWidget);
      expect(find.text('₺12.500,00'), findsOneWidget);
      expect(find.text('−₺6.550,50'), findsOneWidget);
      expect(find.text('Tablo olarak göster'), findsOneWidget);
    });

    testWidgets('hiç veri yoksa grafik yerine açıklama', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: FinanceChart(months: months())),
        ),
      );
      expect(find.byType(BarChart), findsNothing);
      expect(find.textContaining('kayıt yok'), findsOneWidget);
    });
  });

  group('Akışlar', () {
    testWidgets('boş ay: ödeme listesi boş durumu ve eylem', (tester) async {
      final h = await pumpFinance(tester);
      await h.tester.tap(find.byTooltip('Önceki ay'));
      await h.settle();
      await h.tester.tap(find.text('Ödemeler'));
      await h.settle();
      expect(find.text('Ekim 2026 için ödeme yok'), findsOneWidget);
      expect(find.text('Ödeme ekle'), findsWidgets);
    });

    testWidgets('yükleme hatası: Tekrar dene görünür (çevrimdışı mesajı)', (
      tester,
    ) async {
      final h = await pumpFinance(
        tester,
        extraOverrides: [
          paymentsProvider.overrideWith(
            (ref) => throw const AppException(
              AppErrorCode.network,
              AppException.networkMessage,
            ),
          ),
        ],
      );
      expect(find.text('Tekrar dene'), findsWidgets);
      expect(find.text(AppException.networkMessage), findsWidgets);
      expect(h.location, '/finance');
    });

    testWidgets(
      'ödeme sil: listeden hemen kalkar, Geri al ile döner (DELETE gitmez)',
      (tester) async {
        final h = await pumpFinance(tester);
        await h.tester.tap(find.text('Ödemeler'));
        await h.settle();
        expect(find.text('PRJ-501 · Zeynep Arslan'), findsOneWidget);
        await h.tester.tap(find.byTooltip('Ödeme işlemleri').first);
        await h.settle(4);
        await h.tester.tap(find.text('Sil'));
        await h.settle(4);
        expect(find.textContaining('ödeme silindi'), findsOneWidget);
        // En yeni ödeme (Burak Aydın, Kredi Kartı) gizlendi.
        expect(find.text('PRJ-504 · Burak Aydın'), findsNothing);
        await h.tester.tap(find.text('Geri al'));
        await h.settle(6);
        expect(find.text('PRJ-504 · Burak Aydın'), findsOneWidget);
        final all = await h.container.read(paymentsProvider.future);
        expect(all.length, 3);
      },
    );

    testWidgets(
      'ödeme sil: süre dolunca gerçek DELETE gider, özet güncellenir',
      (tester) async {
        final h = await pumpFinance(tester);
        await h.tester.tap(find.text('Ödemeler'));
        await h.settle();
        await h.tester.tap(find.byTooltip('Ödeme işlemleri').first);
        await h.settle(4);
        await h.tester.tap(find.text('Sil'));
        await h.settle(10); // SnackBar animasyonu bitsin; süre sayacı başlasın
        await h.tester.pump(const Duration(seconds: 9));
        await h.settle(20);
        final all = await h.container.read(paymentsProvider.future);
        expect(all.length, 2);
        expect(
          inCard('payments-total', find.text('₺10.000,00')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'ödeme düzenle: alanlar dolu, proje değiştirilemez, kayıt özete yansır',
      (tester) async {
        final h = await pumpFinance(tester);
        await h.tester.tap(find.text('Ödemeler'));
        await h.settle();
        await h.tester.tap(find.text('PRJ-501 · Zeynep Arslan'));
        await h.settle(15);
        expect(find.text('Ödemeyi düzenle'), findsOneWidget);
        final amount = find.byType(TextFormField).first;
        expect(
          tester.widget<TextFormField>(amount).controller!.text,
          '4.000,00',
        );
        expect(
          find.byIcon(Icons.expand_more),
          findsNothing,
        ); // proje seçici yok
        await h.tester.enterText(amount, '4500,50');
        await h.tester.tap(find.text('Güncelle'));
        await h.settle(20);
        expect(h.location, '/finance');
        expect(find.text('Ödeme güncellendi'), findsOneWidget);
        final all = await h.container.read(paymentsProvider.future);
        expect(
          all.firstWhere((p) => p.id == 'pay-1').amount,
          Money.fromKurus(450050),
        );
      },
    );

    testWidgets(
      'proje yükü: projectId ile açılınca proje önceden seçili, UUID yok',
      (tester) async {
        final h = await pumpFinance(
          tester,
          role: UserRole.admin,
          initialLocation: '/finance/expenses/new?projectId=prj-2',
        );
        final scrollable = find.byType(Scrollable).first;
        // Projeye bağlı giderde proje kategorileri (Taşeron...) sunulur.
        expect(find.text('Taşeron'), findsOneWidget);
        await h.tester.scrollUntilVisible(
          find.text('PRJ-502 · Ahmet Şahin'),
          200,
          scrollable: scrollable,
        );
        expect(find.text('PRJ-502 · Ahmet Şahin'), findsOneWidget);
        expect(find.textContaining('prj-'), findsNothing);
        // Projeye bağlı giderde Kişisel kapsam sunulmaz.
        await h.tester.drag(scrollable, const Offset(0, 300));
        await h.settle(3);
        expect(find.widgetWithText(ChoiceChip, 'İşletme'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Ev'), findsNothing);
      },
    );

    testWidgets('sabit gider ekle: form kaydı listeye yansır', (tester) async {
      final h = await pumpFinance(tester);
      await h.tester.ensureVisible(find.text('Sabit giderler'));
      await h.tester.tap(find.text('Sabit giderler'));
      await h.settle();
      await h.tester.tap(find.text('Sabit gider ekle'));
      await h.settle(15);
      expect(find.text('Sabit gider ekle'), findsWidgets);
      await h.tester.enterText(find.byType(TextFormField).first, '1.250,50');
      await h.tester.tap(find.text('Sigorta/SGK'));
      await h.tester.tap(find.text('Kaydet'));
      await h.settle(20);
      expect(h.location, '/finance');
      final list = await h.container.read(recurringProvider.future);
      final added = list.firstWhere((r) => r.category == 'Sigorta/SGK');
      expect(added.amount, Money.fromKurus(125050));
    });
  });
}
