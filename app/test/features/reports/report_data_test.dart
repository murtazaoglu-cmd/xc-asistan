import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/reports/data/report_charts.dart';
import 'package:xc_asistan/features/reports/data/report_models.dart';
import 'package:xc_asistan/features/reports/data/reports_repository.dart';

import '../../helpers/fakes.dart';
import 'harness.dart';

final now = DateTime.utc(2026, 11, 20, 9); // İstanbul: 20 Kasım 2026

ProfitPoint pt(String period, num rev, num biz, [num home = 0]) =>
    ProfitPoint.fromJson({
      'period': period,
      'revenue': rev,
      'businessExpenses': biz,
      'homeExpenses': home,
      'netProfit': rev - biz,
      'netProfitInclHome': rev - biz - home,
    });

void main() {
  group('Modeller', () {
    test('summary: ev giderleri işletme kârına dahil değil', () {
      final s = ReportSummary.fromJson({
        'totalOffers': 6,
        'statusCounts': {'Yeni': 2, 'Kabul Edildi': 1},
        'conversionRate': 16.7,
        'totalRevenue': 12500,
        'activeProjects': 3,
        'businessExpenses': 19050.5,
        'homeExpenses': 12000,
        'expensesByScope': {'dukkan': 10000.5, 'genel': 9050, 'ev': 12000},
        'netProfit': -6550.5,
        'netProfitInclHome': -18550.5,
      });
      expect(s.netProfit, Money.fromKurus(-655050));
      expect(s.netProfit, s.totalRevenue - s.businessExpenses);
      expect(s.homeExpenses, Money.fromTl(12000));
      expect(s.netProfitInclHome, s.netProfit - s.homeExpenses);
      expect(s.expensesDukkan + s.expensesGenel, s.businessExpenses);
      expect(s.expensesEv, s.homeExpenses);
      expect(s.statusCounts['Yeni'], 2);
      expect(s.conversionRate, 16.7);
    });

    test(
      'summary: netProfit alanı yoksa gelir − İŞLETME gideri (ev hariç)',
      () {
        final s = ReportSummary.fromJson({
          'totalRevenue': 1000,
          'businessExpenses': 300,
          'homeExpenses': 500,
        });
        expect(s.netProfit, Money.fromTl(700));
        expect(s.netProfitInclHome, Money.fromTl(200));
      },
    );

    test('summary ve satırlar boş/null gövdede çökmez', () {
      final s = ReportSummary.fromJson({});
      expect(s.totalRevenue, Money.zero);
      expect(s.statusCounts, isEmpty);
      final p = ProfitPoint.fromJson({'period': null});
      expect(p.isEmpty, isTrue);
      expect(p.parsed, isNull);
    });

    test('dönem ayrıştırma', () {
      expect(ReportPeriod.tryParse('2026-11')!.ordinal, 2026 * 12 + 10);
      expect(ReportPeriod.tryParse('2026-11')!.month, 11);
      expect(ReportPeriod.tryParse('2026')!.month, isNull);
      expect(ReportPeriod.tryParse('2026-13'), isNull);
      expect(ReportPeriod.tryParse('abc'), isNull);
    });

    test('hizmet dağılımı: azalan sıra ve yüzde', () {
      final r = ServiceShare.withPercent([
        const ServiceShare(service: 'Bakım', count: 1),
        const ServiceShare(service: 'Montaj', count: 3),
      ]);
      expect(r.first.item.service, 'Montaj');
      expect(r.first.percent, 75);
      expect(
        ServiceShare.withPercent([const ServiceShare(service: 'x', count: 0)])
            .single
            .percent,
        0,
      );
      expect(ServiceShare.withPercent([]), isEmpty);
    });

    test(
      'proje kârlılığı: tahsilat − gider; ev gideri ve projesiz gider sayılmaz',
      () {
        final list = ProjectProfit.compute(
          [
            {
              'id': 'p1',
              'code': 'PRJ-1',
              'customer_name': 'Ali',
              'total_amount': 10000,
              'paid_amount': 6000,
            },
            {
              'id': 'p2',
              'code': 'PRJ-2',
              'customer_name': 'Veli',
              'total_amount': 500,
              'paid_amount': 800,
            },
          ],
          [
            {'project_id': 'p1', 'amount': 1500.5, 'scope': 'genel'},
            {'project_id': 'p1', 'amount': 500, 'scope': 'dukkan'},
            {'project_id': 'p1', 'amount': 9999, 'scope': 'ev'},
            {'project_id': null, 'amount': 777, 'scope': 'genel'},
          ],
        );
        final a = list.first;
        expect(a.expenses, Money.fromKurus(200050));
        expect(a.profit, Money.fromKurus(399950));
        expect(a.outstanding, Money.fromTl(4000));
        expect(a.marginPercent, closeTo(66.66, 0.01));
        final b = list.last;
        expect(b.outstanding, Money.zero); // fazla ödeme
        expect(b.profit, Money.fromTl(800));
      },
    );

    test('tahsilat yoksa marj null ve zarar negatif', () {
      final p = ProjectProfit.compute(
        [
          {'id': 'p', 'total_amount': 100, 'paid_amount': 0},
        ],
        [
          {'project_id': 'p', 'amount': 40, 'scope': 'genel'},
        ],
      ).single;
      expect(p.marginPercent, isNull);
      expect(p.profit.isNegative, isTrue);
    });
  });

  group('CompactMoney (kısa para biçimi)', () {
    String f(num tl) => CompactMoney.format(Money.fromTl(tl));
    test('binlik/milyonluk birimler', () {
      expect(f(0), '₺0');
      expect(f(850), '₺850');
      expect(f(1500), '₺1,5 B');
      expect(f(12000), '₺12 B');
      expect(f(12500), '₺12,5 B');
      expect(f(120000), '₺120 B');
      expect(f(1200000), '₺1,2 Mn');
      expect(f(3000000000), '₺3 Mr');
    });
    test('sınır: 999,96 B → 1 Mn; negatif işaret', () {
      expect(f(999960), '₺1 Mn');
      expect(f(999.7), '₺1 B');
      expect(f(-12000), '−₺12 B');
      expect(CompactMoney.format(Money.fromTl(12000), symbol: false), '12 B');
    });
  });

  group('ChartScale', () {
    test('güzel adım ve 4 eşit aralık', () {
      final s = ChartScale.nice(12500);
      expect(s.step, 5000);
      expect(s.max, 20000);
      expect(s.tickValues, [0, 5000, 10000, 15000, 20000]);
      expect(ChartScale.nice(1000).max, 1000);
      expect(ChartScale.nice(7).step, 2);
      expect(ChartScale.nice(310000).step, 100000);
    });
    test('veri yok / sıfır: makul varsayılan', () {
      expect(ChartScale.nice(0).max, 1000);
      expect(ChartScale.nice(double.nan).max, 1000);
    });
    test('en büyük değer her zaman ölçeğe sığar', () {
      for (final v in [1, 3, 99, 101, 2499, 2500, 2501, 99999, 1234567]) {
        final s = ChartScale.nice(v.toDouble());
        expect(s.max >= v, isTrue, reason: '$v');
      }
    });
  });

  group('MoneyChartData.monthly (12 → 6 ay penceresi)', () {
    final points = [
      pt('2026-11', 12500, 7050.5, 12000),
      pt('2026-10', 8900, 6100, 12000),
      pt('2026-09', 5200, 4100, 12000),
      pt('2026-08', 0, 0, 0), // kayıtlı ama hareketsiz
      // 2026-07 ve 2026-06: kayıt yok
      pt('2026-05', 31000, 22400, 12000),
      pt('2026-01', 14000, 9900, 12000),
      pt('2025-12', 1000, 500),
      pt('2025-10', 99999, 99999), // pencere dışı
    ];
    final d = MoneyChartData.monthly(points, now: now);

    test('12 sürekli ay, eskiden yeniye; görünür pencere 6', () {
      expect(d.bars.length, 12);
      expect(d.bars.first.key, '2025-12');
      expect(d.bars.last.key, '2026-11');
      expect(d.visibleCount, 6);
      expect(d.visibleBars.length, 6);
      expect(d.visibleBars.first.key, '2026-06');
      expect(d.visibleBars.last.key, '2026-11');
      // süreklilik: ardışık aylar
      for (var i = 1; i < d.bars.length; i++) {
        final a = ReportPeriod.tryParse(d.bars[i - 1].key)!;
        final b = ReportPeriod.tryParse(d.bars[i].key)!;
        expect(b.ordinal - a.ordinal, 1);
      }
      expect(d.bars.any((b) => b.key == '2025-10'), isFalse);
    });

    test('kısaltılmış ay adları; yıl yalnız ocakta ve ilk çubukta', () {
      expect(d.bars.map((b) => b.label).take(3), ['Ara', 'Oca', 'Şub']);
      expect(d.bars.last.label, 'Kas');
      expect(d.bars.first.yearLabel, '2025');
      expect(d.bars[1].yearLabel, '2026');
      expect(d.bars[2].yearLabel, isNull);
      expect(d.bars.last.yearLabel, isNull);
      expect(d.bars.last.longLabel, 'Kasım 2026');
    });

    test('boş ay: kaydı olmayan ve sıfır kayıtlı ay hasData=false', () {
      ChartBar bar(String k) => d.bars.firstWhere((b) => b.key == k);
      expect(bar('2026-07').hasData, isFalse);
      expect(bar('2026-07').revenue, Money.zero);
      expect(bar('2026-08').hasData, isFalse);
      expect(bar('2026-09').hasData, isTrue);
    });

    test(
      'iki seri: gider yalnız işletme; ev gideri ayrı, kâra dahil değil',
      () {
        final nov = d.bars.last;
        expect(nov.revenue, Money.fromTl(12500));
        expect(nov.expense, Money.fromKurus(705050));
        expect(nov.homeExpense, Money.fromTl(12000));
        expect(nov.net, nov.revenue - nov.expense);
        expect(nov.netInclHome, nov.net - nov.homeExpense);
        expect(nov.net, isNot(nov.netInclHome));
      },
    );

    test('görünür toplam yalnız son 6 ay', () {
      final t = d.visibleTotals();
      expect(t.revenue, Money.fromTl(12500 + 8900 + 5200));
      expect(t.expense, Money.fromKurus(705050 + 610000 + 410000));
    });

    test('varsayılan seçim: verisi olan en yeni dönem', () {
      expect(d.defaultSelected, 11);
      final onlyOld = MoneyChartData.monthly([pt('2026-05', 1, 1)], now: now);
      expect(onlyOld.bars[onlyOld.defaultSelected].key, '2026-05');
      final none = MoneyChartData.monthly([], now: now);
      expect(none.hasAnyData, isFalse);
      expect(none.defaultSelected, 11);
    });

    test('yıl sınırı: ocak ayında pencere geçen yılı kapsar', () {
      final jan = MoneyChartData.monthly([
        pt('2026-12', 5, 1),
      ], now: DateTime.utc(2027, 1, 15, 9));
      expect(jan.bars.last.key, '2027-01');
      expect(jan.bars.any((b) => b.key == '2026-12' && b.hasData), isTrue);
      expect(jan.bars.first.key, '2026-02');
    });

    test('İstanbul günü: 31 Ara 22:30 UTC aslında 1 Oca (İstanbul)', () {
      final d2 = MoneyChartData.monthly(
        [],
        now: DateTime.utc(2026, 12, 31, 22, 30),
      );
      expect(d2.bars.last.key, '2027-01');
    });

    test('bozuk dönem anahtarları yok sayılır', () {
      final d3 = MoneyChartData.monthly([
        pt('xx', 1, 1),
        pt('2026-13', 1, 1),
      ], now: now);
      expect(d3.hasAnyData, isFalse);
    });
  });

  group('MoneyChartData.yearly', () {
    test('5 yıl, eksik yıl boş', () {
      final d = MoneyChartData.yearly([
        pt('2026', 100, 40, 10),
        pt('2024', 50, 20),
      ], now: now);
      expect(d.bars.map((b) => b.key), [
        '2022',
        '2023',
        '2024',
        '2025',
        '2026',
      ]);
      expect(d.bars[3].hasData, isFalse);
      expect(d.bars.last.expense, Money.fromTl(40));
      expect(d.bars.last.longLabel, '2026');
      expect(d.bars.last.yearLabel, isNull);
    });
  });

  group('Repository (sahte Dio)', () {
    test('summary, profit/revenue range, service-distribution', () async {
      final a = ScriptedAdapter((i, o) {
        switch (o.path) {
          case '/reports/summary':
            return ScriptedResponse(200, {
              'totalRevenue': 10,
              'businessExpenses': 4,
              'homeExpenses': 3,
            });
          case '/reports/profit':
            return ScriptedResponse(200, [
              {
                'period': '2026-11',
                'revenue': 5,
                'businessExpenses': 2,
                'homeExpenses': 1,
                'netProfit': 3,
                'netProfitInclHome': 2,
              },
            ]);
          case '/reports/revenue':
            return ScriptedResponse(200, [
              {'period': '2026', 'total': 99.5},
            ]);
          default:
            return ScriptedResponse(200, [
              {'service': 'Montaj', 'count': 2},
            ]);
        }
      });
      final repo = HttpReportsRepository(apiWith(a));
      expect((await repo.summary()).netProfit, Money.fromTl(6));
      final p = await repo.profit(ReportRange.yearly);
      expect(a.requests[1].queryParameters, {'range': 'yearly'});
      expect(p.single.homeExpenses, Money.fromTl(1));
      final r = await repo.revenue(ReportRange.monthly);
      expect(a.requests[2].queryParameters, {'range': 'monthly'});
      expect(r.single.total, Money.fromKurus(9950));
      expect((await repo.serviceDistribution()).single.count, 2);
    });

    test('projectProfitability: 200\'erli sayfalar + /expenses', () async {
      List<Map<String, dynamic>> page(int from, int n) => [
        for (var i = from; i < from + n; i++)
          {
            'id': 'p$i',
            'code': 'PRJ-$i',
            'customer_name': 'M$i',
            'total_amount': 100,
            'paid_amount': 50,
          },
      ];
      final a = ScriptedAdapter((i, o) {
        if (o.path == '/projects') {
          final off = o.queryParameters['offset'] as int;
          return ScriptedResponse(
            200,
            off == 0 ? page(0, 200) : page(200, 50),
            {'x-total-count': '250'},
          );
        }
        return ScriptedResponse(200, [
          {'project_id': 'p0', 'amount': 10, 'scope': 'genel'},
        ]);
      });
      final list = await HttpReportsRepository(apiWith(a))
          .projectProfitability();
      expect(list.length, 250);
      final proj = a.requests.where((r) => r.path == '/projects').toList();
      expect(proj.map((r) => r.queryParameters['offset']), [0, 200]);
      expect(proj.first.queryParameters['limit'], 200);
      expect(list.first.expenses, Money.fromTl(10));
    });
  });
}
