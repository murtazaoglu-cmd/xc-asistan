import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/finance/data/finance_calc.dart';
import 'package:xc_asistan/features/finance/data/finance_models.dart';

Payment pay(double tl, DateTime at) => Payment(
  id: 'p${at.microsecondsSinceEpoch}$tl',
  projectId: 'x',
  amount: Money.fromTl(tl),
  method: 'Havale',
  paidAt: at,
);

Expense exp(double tl, String scope, DateTime at) => Expense(
  id: 'e${at.microsecondsSinceEpoch}$tl$scope',
  category: 'K',
  amount: Money.fromTl(tl),
  scopeRaw: scope,
  expenseDate: at,
);

void main() {
  final nov = const YearMonth(2026, 11);

  group('YearMonth (İstanbul)', () {
    test('ay aritmetiği ve etiketler', () {
      expect(nov.previous, const YearMonth(2026, 10));
      expect(const YearMonth(2026, 1).previous, const YearMonth(2025, 12));
      expect(const YearMonth(2026, 12).next, const YearMonth(2027, 1));
      expect(nov.label, 'Kasım 2026');
      expect(nov.shortLabel, 'Kas');
      expect(nov.period, '2026-11');
      expect(nov.addMonths(-11), const YearMonth(2025, 12));
    });

    test('İstanbul gün sınırı: 31 Ekim 21:30 UTC = 1 Kasım 00:30', () {
      expect(YearMonth.of(DateTime.utc(2026, 10, 31, 21, 30)), nov);
      expect(
        YearMonth.of(DateTime.utc(2026, 10, 31, 20, 59)),
        const YearMonth(2026, 10),
      );
      expect(nov.contains(DateTime.utc(2026, 11, 30, 20, 59)), isTrue);
      expect(nov.contains(DateTime.utc(2026, 11, 30, 21, 0)), isFalse);
    });
  });

  group('Aylık toplam ve ev gideri ayrımı', () {
    final d = DateTime.utc(2026, 11, 15, 9);
    test('kâr = gelir − (dukkan+genel); ev ayrı', () {
      final t = FinanceCalc.totalsFor(
        [pay(12500, d)],
        [
          exp(15000, 'dukkan', d),
          exp(3200.5, 'genel', d),
          exp(850, 'genel', d),
          exp(12000, 'ev', d),
        ],
        nov,
      );
      expect(t.revenue, Money.fromTl(12500));
      expect(t.businessExpense, Money.fromTl(19050.5));
      expect(t.personalExpense, Money.fromTl(12000));
      expect(t.profit, Money.fromTl(-6550.5));
      expect(t.profitInclPersonal, Money.fromTl(-18550.5));
      expect(t.hasData, isTrue);
    });

    test('yalnız ev gideri olan ay: kâr eksiye DÜŞMEZ', () {
      final t = FinanceCalc.totalsFor([], [exp(12000, 'ev', d)], nov);
      expect(t.profit, Money.zero);
      expect(t.personalExpense, Money.fromTl(12000));
    });

    test('kuruş doğruluğu: 0,10 + 0,20 tam 0,30', () {
      final t = FinanceCalc.totalsFor([pay(0.1, d), pay(0.2, d)], [], nov);
      expect(t.revenue.kurus, 30);
      expect(t.revenue.toApiString(), '0.30');
    });

    test('başka ay kayıtları sayılmaz', () {
      final t = FinanceCalc.totalsFor(
        [pay(100, DateTime.utc(2026, 10, 10))],
        [exp(50, 'genel', DateTime.utc(2026, 12, 2))],
        nov,
      );
      expect(t.hasData, isFalse);
      expect(t.revenue, Money.zero);
    });

    test('marj yüzdesi (tamsayı, negatif olabilir, gelir yoksa null)', () {
      MonthTotals t(double r, double b) => MonthTotals(
        revenue: Money.fromTl(r),
        businessExpense: Money.fromTl(b),
        personalExpense: Money.zero,
      );
      expect(t(1000, 660).marginPercent, 34);
      expect(t(1000, 1500).marginPercent, -50);
      expect(t(0, 500).marginPercent, isNull);
    });
  });

  group('Grafik penceresi', () {
    test('en çok 6 ay, eskiden yeniye, seçili ayda biter', () {
      final w = FinanceCalc.chartWindow([], [], nov);
      expect(w.length, 6);
      expect(w.first.month, const YearMonth(2026, 6));
      expect(w.last.month, nov);
    });

    test('istenen ay sayısı 6 ile sınırlanır; en az 1', () {
      expect(FinanceCalc.chartWindow([], [], nov, months: 12).length, 6);
      expect(FinanceCalc.chartWindow([], [], nov, months: 0).length, 1);
      expect(FinanceCalc.chartWindow([], [], nov, months: 3).length, 3);
    });

    test('iki seri; gider yalnız işletme (ev hariç); boş ay hasData=false', () {
      final oct = DateTime.utc(2026, 10, 5, 9);
      final w = FinanceCalc.chartWindow(
        [pay(1000, oct)],
        [exp(300, 'genel', oct), exp(9999, 'ev', oct)],
        nov,
      );
      final octM = w.firstWhere((m) => m.month == const YearMonth(2026, 10));
      expect(octM.revenue, Money.fromTl(1000));
      expect(octM.expense, Money.fromTl(300));
      expect(octM.net, Money.fromTl(700));
      expect(octM.hasData, isTrue);
      expect(w.last.hasData, isFalse);
    });

    test('yıl dönümünde pencere Aralık/Ocak’ı doğru geçer', () {
      final w = FinanceCalc.chartWindow([], [], const YearMonth(2027, 2));
      expect(w.map((m) => m.month.period).toList(), [
        '2026-09',
        '2026-10',
        '2026-11',
        '2026-12',
        '2027-01',
        '2027-02',
      ]);
    });
  });

  group('Alacaklar', () {
    ProjectRef proj(String name, double total, double paid, {DateTime? end}) =>
        ProjectRef(
          id: name,
          code: 'PRJ-$name',
          customerName: name,
          total: Money.fromTl(total),
          paid: Money.fromTl(paid),
          endDate: end,
        );
    final now = DateTime.utc(2026, 11, 20, 8);

    test('kalanı olmayan çıkar; vadesi geçenler önce, sonra kalan azalan', () {
      final list = FinanceCalc.receivables([
        proj('a', 1000, 1000),
        proj('b', 5000, 0, end: DateTime.utc(2026, 12, 1)),
        proj('c', 2000, 500, end: DateTime.utc(2026, 11, 10, 9)),
        proj('d', 9000, 0, end: DateTime.utc(2026, 11, 1, 9)),
        proj('e', 300, 100),
      ], now: now);
      expect(list.map((r) => r.project.customerName).toList(), [
        'd',
        'c',
        'b',
        'e',
      ]);
      expect(list.first.isOverdue, isTrue);
      expect(list.first.overdueDays, 19);
      expect(list[2].isOverdue, isFalse);
      expect(
        FinanceCalc.totalReceivable(list),
        Money.fromTl(9000 + 1500 + 5000 + 200),
      );
    });

    test('bitiş günü bugünse vadesi geçmiş sayılmaz', () {
      final list = FinanceCalc.receivables([
        proj('x', 100, 0, end: DateTime.utc(2026, 11, 20, 5)),
      ], now: now);
      expect(list.single.isOverdue, isFalse);
    });
  });

  group('Yardımcılar', () {
    test('percentOf kuruş tamsayısı', () {
      expect(
        FinanceCalc.percentOf(Money.fromKurus(2604600), 50).kurus,
        1302300,
      );
      expect(FinanceCalc.percentOf(Money.fromKurus(1001), 50).kurus, 501);
      expect(
        FinanceCalc.percentOf(Money.fromTl(26046), 25),
        Money.fromTl(6511.5),
      );
    });

    test('eksen etiketi kısa', () {
      expect(FinanceCalc.compact(Money.fromTl(850)), '₺850');
      expect(FinanceCalc.compact(Money.fromTl(12000)), '₺12 bin');
      expect(FinanceCalc.compact(Money.fromTl(1500)), '₺1,5 bin');
      expect(FinanceCalc.compact(Money.fromTl(1200000)), '₺1,2 Mn');
      expect(FinanceCalc.compact(Money.fromTl(-5000)), '−₺5 bin');
      expect(FinanceCalc.compact(Money.zero), '₺0');
    });
  });

  tearDown(() => Ist.clock = DateTime.now);
}
