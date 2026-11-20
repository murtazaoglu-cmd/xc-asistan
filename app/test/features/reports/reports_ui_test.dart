import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/demo/demo_adapter.dart';
import 'package:xc_asistan/core/demo/demo_db.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/features/reports/data/report_charts.dart';
import 'package:xc_asistan/features/reports/data/report_models.dart';
import 'package:xc_asistan/features/reports/data/reports_repository.dart';
import 'package:xc_asistan/features/reports/presentation/money_chart.dart';
import 'package:xc_asistan/features/reports/presentation/reports_screen.dart';

import 'harness.dart';
import 'report_data_test.dart' show pt;

class FakeReportsRepo implements ReportsRepository {
  FakeReportsRepo({this.profitError});
  Object? profitError;
  final List<ReportRange> profitCalls = [];

  @override
  Future<ReportSummary> summary() async => ReportSummary.fromJson({
    'totalOffers': 6,
    'conversionRate': 16.7,
    'totalRevenue': 12500,
    'activeProjects': 3,
    'businessExpenses': 19050.5,
    'homeExpenses': 12000,
    'netProfit': -6550.5,
    'netProfitInclHome': -18550.5,
  });

  @override
  Future<List<ProfitPoint>> profit(ReportRange range) async {
    profitCalls.add(range);
    if (profitError != null) throw profitError!;
    final n = Ist.wall(Ist.now());
    String p(int back) {
      final ord = n.year * 12 + n.month - 1 - back;
      return '${ord ~/ 12}-${(ord % 12 + 1).toString().padLeft(2, '0')}';
    }

    if (range == ReportRange.yearly) {
      return [pt('${n.year}', 99000, 60000, 120000)];
    }
    return [pt(p(0), 12500, 7050.5, 12000), pt(p(1), 8900, 6100, 12000)];
  }

  @override
  Future<List<RevenuePoint>> revenue(ReportRange range) async => [];

  @override
  Future<List<ServiceShare>> serviceDistribution() async => const [
    ServiceShare(service: 'Montaj', count: 3),
    ServiceShare(service: 'Bakım', count: 1),
  ];

  @override
  Future<List<ProjectProfit>> projectProfitability() async =>
      ProjectProfit.compute(
        [
          {
            'id': 'p1',
            'code': 'PRJ-1',
            'customer_name': 'Ali Kaya',
            'service': 'Montaj',
            'total_amount': 10000,
            'paid_amount': 6000,
          },
          {
            'id': 'p2',
            'code': 'PRJ-2',
            'customer_name': 'Veli Tan',
            'total_amount': 2000,
            'paid_amount': 500,
          },
        ],
        [
          {'project_id': 'p2', 'amount': 900, 'scope': 'genel'},
        ],
      );
}

final nowFix = DateTime.utc(2026, 11, 20, 9);

MoneyChartData chartData12() => MoneyChartData.monthly([
  pt('2026-11', 12500, 7050.5, 12000),
  pt('2026-10', 8900, 6100, 12000),
  pt('2026-09', 5200, 4100, 12000),
  pt('2026-05', 31000, 22400, 12000),
], now: nowFix);

Future<void> pumpChart(
  WidgetTester t,
  MoneyChartData data, {
  double width = 360,
}) async {
  await pumpScreen(
    t,
    Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: MoneyBarChart(data: data),
        ),
      ),
    ),
    size: Size(width, 1200),
  );
  await settle(t, 4);
}

ScrollPosition chartScroll(WidgetTester t) => t
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('chart-scroll')),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

void main() {
  group('Para grafiği', () {
    testWidgets(
      'açılış: son veri ayı seçili, değer kutusu ve iki seri açıklaması',
      (t) async {
        await pumpChart(t, chartData12());
        expect(
          find.text('Gelir'),
          findsOneWidget,
        ); // açıklama (grafiğin üstünde)
        expect(find.text('Gider (işletme)'), findsWidgets);
        final box = find.byKey(const Key('value-box'));
        expect(
          find.descendant(of: box, matching: find.text('Kasım 2026')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: box, matching: find.text('₺12.500,00')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: box, matching: find.text('₺7.050,50')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: box, matching: find.text('₺5.449,50')),
          findsOneWidget,
        ); // net
      },
    );

    testWidgets('ev giderleri ayrı satırda ve "kâra dahil değil" der', (
      t,
    ) async {
      await pumpChart(t, chartData12());
      final box = find.byKey(const Key('value-box'));
      expect(
        find.descendant(
          of: box,
          matching: find.text('Ev giderleri (kâra dahil değil)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: box, matching: find.text('₺12.000,00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: box, matching: find.text('Ev giderleri dahil net')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: box, matching: find.text('−₺6.550,50')),
        findsOneWidget,
      );
    });

    testWidgets(
      'önceki/sonraki ay düğmeleri; boş ay "kayıt yok" der (₺0 yazmaz)',
      (t) async {
        await pumpChart(t, chartData12());
        // Kas → Eki → Eyl → Ağu (boş)
        for (var i = 0; i < 3; i++) {
          await t.tap(find.byTooltip('Önceki ay'));
          await t.pump();
        }
        final box = find.byKey(const Key('value-box'));
        expect(
          find.descendant(of: box, matching: find.text('Ağustos 2026')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: box, matching: find.text('Bu ay kayıt yok.')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: box, matching: find.textContaining('₺')),
          findsNothing,
        );
        await t.tap(find.byTooltip('Sonraki ay'));
        await t.pump();
        expect(
          find.descendant(of: box, matching: find.text('Eylül 2026')),
          findsOneWidget,
        );
      },
    );

    testWidgets('en eski/en yeni uçta düğme pasif', (t) async {
      await pumpChart(t, chartData12());
      IconButton b(String tip) => t.widget<IconButton>(
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == tip),
      );
      expect(b('Sonraki ay').onPressed, isNull);
      expect(b('Önceki ay').onPressed, isNotNull);
    });

    testWidgets(
      '12 ay: 6 ay görünür, geriye yatay kaydırılır; en yeni sağda açılır',
      (t) async {
        await pumpChart(t, chartData12());
        final pos = chartScroll(t);
        expect(pos.maxScrollExtent > 0, isTrue);
        expect(pos.pixels, 0); // reverse: 0 = sağ uç (en yeni)
        final viewport = t.getSize(find.byKey(const Key('chart-scroll'))).width;
        final content = viewport + pos.maxScrollExtent;
        // görünür pencere = 6 ay: içerik / görünür ≈ 12 / 6
        expect(content / viewport, closeTo(2.0, 0.1));
        // geçmişe kaydır
        await t.drag(
          find.byKey(const Key('chart-scroll')),
          const Offset(400, 0),
        );
        await t.pump();
        expect(chartScroll(t).pixels > 0, isTrue);
      },
    );

    testWidgets('6 ay ya da daha azı: kaydırma yok', (t) async {
      final six = MoneyChartData(chartData12().bars.sublist(6));
      await pumpChart(t, six);
      expect(chartScroll(t).maxScrollExtent, 0);
    });

    testWidgets(
      'dar ekranda çubuk grubu en az 48 dp yer alır (etiketler çakışmaz)',
      (t) async {
        await pumpChart(t, chartData12(), width: 320);
        final pos = chartScroll(t);
        final viewport = t.getSize(find.byKey(const Key('chart-scroll'))).width;
        expect((viewport + pos.maxScrollExtent) / 12 >= 48, isTrue);
      },
    );

    testWidgets('eksen etiketleri kısa para biçiminde (₺5 B …)', (t) async {
      await pumpChart(t, chartData12());
      expect(find.text('₺0'), findsOneWidget);
      expect(find.textContaining(' B'), findsWidgets);
      expect(find.text('₺10 B'), findsOneWidget);
    });

    testWidgets('tablo olarak göster: tüm dönemler, boş ay "kayıt yok"', (
      t,
    ) async {
      await pumpChart(t, chartData12());
      expect(find.byKey(const Key('chart-table')), findsNothing);
      await t.tap(find.text('Tablo olarak göster'));
      await t.pump();
      final table = find.byKey(const Key('chart-table'));
      expect(table, findsOneWidget);
      expect(
        find.descendant(of: table, matching: find.text('Kas 26')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: table, matching: find.text('kayıt yok')),
        findsWidgets,
      );
      await t.tap(find.text('Tabloyu gizle'));
      await t.pump();
      expect(find.byKey(const Key('chart-table')), findsNothing);
    });

    testWidgets('ekran okuyucu için özet etiketi', (t) async {
      final h = t.ensureSemantics();
      await pumpChart(t, chartData12());
      expect(
        find.bySemanticsLabel(RegExp('Gelir ve gider grafiği.*toplam gelir')),
        findsOneWidget,
      );
      h.dispose();
    });

    testWidgets('yıllık: tek çubuk grubu, kayıtsız yıl boş', (t) async {
      final y = MoneyChartData.yearly([
        pt('2026', 99000, 60000, 120000),
      ], now: nowFix);
      await pumpChart(t, y);
      final box = find.byKey(const Key('value-box'));
      expect(
        find.descendant(of: box, matching: find.text('2026')),
        findsOneWidget,
      );
      await t.tap(find.byTooltip('Önceki yıl'));
      await t.pump();
      expect(find.text('Bu yıl kayıt yok.'), findsOneWidget);
    });
  });

  group('Raporlar ekranı', () {
    testWidgets('genel durum: net kâr işletme; ev giderleri ayrı satır', (
      t,
    ) async {
      await pumpScreen(
        t,
        const ReportsScreen(),
        size: const Size(400, 4000),
        overrides: [
          reportsRepositoryProvider.overrideWithValue(FakeReportsRepo()),
        ],
      );
      await settle(t);
      expect(find.text('Net zarar (işletme)'), findsOneWidget);
      expect(find.text('−₺6.550,50'), findsWidgets);
      expect(find.text('Net kâr = gelir − işletme gideri.'), findsOneWidget);
      // ev giderleri ayrı satır, "dahil değil"
      expect(find.text('Ev giderleri (kâra dahil değil)'), findsWidgets);
      expect(find.text('Ev giderleri dahil net'), findsWidgets);
      expect(find.text('−₺18.550,50'), findsOneWidget);
      expect(find.text('%16,7'), findsOneWidget);
    });

    testWidgets('tahsilat ve proje kârlılığı bölümleri', (t) async {
      await pumpScreen(
        t,
        const ReportsScreen(),
        size: const Size(400, 4000),
        overrides: [
          reportsRepositoryProvider.overrideWithValue(FakeReportsRepo()),
        ],
      );
      await settle(t);
      expect(find.text('Tahsilat'), findsOneWidget);
      expect(find.text('Kalan alacak'), findsOneWidget);
      expect(find.text('₺12.000,00'), findsWidgets); // sözleşme toplamı
      expect(
        find.text('Proje kârlılığı'),
        findsNothing,
      ); // sözlük: "İş kârlılığı"
      expect(find.text('İş kârlılığı'), findsOneWidget);
      // en kârlı önce: Ali (6000) → Veli (500-900 = -400)
      final yA = t.getTopLeft(find.text('Ali Kaya').last).dy;
      final yV = t.getTopLeft(find.text('Veli Tan').last).dy;
      expect(yA < yV, isTrue);
      expect(find.text('−₺400,00'), findsOneWidget);
    });

    testWidgets('hizmet dağılımı sıralı yüzdeli liste', (t) async {
      await pumpScreen(
        t,
        const ReportsScreen(),
        size: const Size(400, 4000),
        overrides: [
          reportsRepositoryProvider.overrideWithValue(FakeReportsRepo()),
        ],
      );
      await settle(t);
      expect(find.text('3 · %75'), findsOneWidget);
      expect(find.text('1 · %25'), findsOneWidget);
    });

    testWidgets('aylık/yıllık geçiş yeni aralığı ister', (t) async {
      final repo = FakeReportsRepo();
      await pumpScreen(
        t,
        const ReportsScreen(),
        size: const Size(400, 4000),
        overrides: [reportsRepositoryProvider.overrideWithValue(repo)],
      );
      await settle(t);
      expect(repo.profitCalls, [ReportRange.monthly]);
      await t.tap(find.text('Yıllık'));
      await settle(t);
      expect(repo.profitCalls.last, ReportRange.yearly);
    });

    testWidgets('grafik hatası yalnız o bölümü bozar; Tekrar dene görünür', (
      t,
    ) async {
      final repo = FakeReportsRepo(
        profitError: const AppException(
          AppErrorCode.network,
          AppException.networkMessage,
        ),
      );
      await pumpScreen(
        t,
        const ReportsScreen(),
        size: const Size(400, 4000),
        overrides: [reportsRepositoryProvider.overrideWithValue(repo)],
      );
      await settle(t);
      expect(find.text(AppException.networkMessage), findsOneWidget);
      expect(find.text('Tekrar dene'), findsOneWidget);
      expect(find.text('Genel durum'), findsOneWidget);
      expect(find.text('Net zarar (işletme)'), findsOneWidget);
    });

    testWidgets('rol görünürlüğü: saha göremez; A/M/O ve personel görür', (
      t,
    ) async {
      await pumpScreen(
        t,
        const ReportsScreen(),
        role: UserRole.saha,
        overrides: [
          reportsRepositoryProvider.overrideWithValue(FakeReportsRepo()),
        ],
      );
      await settle(t);
      expect(find.text('Bu bölüm için yetkiniz yok'), findsOneWidget);
      expect(find.text('Genel durum'), findsNothing);
      for (final role in [
        UserRole.admin,
        UserRole.muhasebe,
        UserRole.ortak,
        UserRole.personel,
      ]) {
        await pumpScreen(
          t,
          const ReportsScreen(),
          role: role,
          overrides: [
            reportsRepositoryProvider.overrideWithValue(FakeReportsRepo()),
          ],
        );
        await settle(t);
        expect(find.text('Genel durum'), findsOneWidget, reason: role.api);
      }
    });
  });

  group('DEMO uçları', () {
    ReportsRepository demo(String role) {
      final db = DemoDb(now: DateTime.utc(2026, 11, 20, 8));
      final dio = Dio(BaseOptions(baseUrl: 'https://demo.test/api'))
        ..httpClientAdapter = DemoHttpAdapter(db, latency: Duration.zero)
        ..options.headers['Authorization'] = 'Bearer demo-token-$role';
      return HttpReportsRepository(ApiClient(dio));
    }

    test(
      'aylık seri seyrek (boş aylar), yıllık iki yıl, ev gideri ayrı',
      () async {
        final r = demo('admin');
        final monthly = await r.profit(ReportRange.monthly);
        final data = MoneyChartData.monthly(monthly, now: Ist.now());
        expect(data.hasAnyData, isTrue);
        expect(data.bars.where((b) => !b.hasData).length, greaterThan(3));
        final cur = data.bars.last;
        expect(cur.net, cur.revenue - cur.expense);
        expect(cur.homeExpense.isPositive, isTrue);
        final yearly = await r.profit(ReportRange.yearly);
        expect(yearly.length, 2);
        final s = await r.summary();
        expect(s.netProfit, s.totalRevenue - s.businessExpenses);
        expect(s.netProfitInclHome, s.netProfit - s.homeExpenses);
        expect((await r.serviceDistribution()), isNotEmpty);
        expect((await r.revenue(ReportRange.monthly)), isNotEmpty);
        final projects = await r.projectProfitability();
        expect(projects, isNotEmpty);
      },
    );

    test('saha 403', () async {
      await expectLater(
        demo('saha').summary(),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'c',
            AppErrorCode.forbidden,
          ),
        ),
      );
    });
  });
}
