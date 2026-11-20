// Saf para hesapları (UI'sız, testlenir). Tüm toplamlar tamsayı kuruştur (double YOK).
// Kural (sözleşme §13): işletme kârı = tahsilat − (dukkan + genel giderler). `ev` (kişisel)
// giderler kâra DAHİL DEĞİLDİR; ayrı satırda gösterilir.
import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/formatters.dart';
import '../../../core/util/money.dart';
import 'finance_models.dart';

/// İstanbul takvim ayı (yıl + ay).
@immutable
class YearMonth implements Comparable<YearMonth> {
  const YearMonth(this.year, this.month);

  final int year;

  /// 1-12
  final int month;

  /// Verilen anın İstanbul ayı.
  factory YearMonth.of(DateTime instant) {
    final w = Ist.wall(instant);
    return YearMonth(w.year, w.month);
  }

  factory YearMonth.now() => YearMonth.of(Ist.now());

  YearMonth addMonths(int n) {
    final idx = year * 12 + (month - 1) + n;
    return YearMonth(idx ~/ 12, idx % 12 + 1);
  }

  YearMonth get previous => addMonths(-1);
  YearMonth get next => addMonths(1);

  /// [başlangıç, sonraki ay başı) — İstanbul sınırları.
  InstantRange get range => InstantRange(
    Ist.fromWall(year, month, 1),
    Ist.fromWall(year, month + 1, 1),
  );

  bool contains(DateTime? instant) =>
      instant != null && range.contains(instant);

  /// "Kasım 2026"
  String get label => '${Fmt.monthsLong[month - 1]} $year';

  /// "Kas"
  String get shortLabel => Fmt.monthsShort[month - 1];

  /// "Kas 2026"
  String get mediumLabel => '$shortLabel $year';

  /// "2026-11" (sözleşmedeki `period` biçimi)
  String get period => '$year-${month.toString().padLeft(2, '0')}';

  @override
  int compareTo(YearMonth other) =>
      (year * 12 + month).compareTo(other.year * 12 + other.month);

  bool operator <(YearMonth o) => compareTo(o) < 0;
  bool operator >(YearMonth o) => compareTo(o) > 0;
  bool operator <=(YearMonth o) => compareTo(o) <= 0;
  bool operator >=(YearMonth o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => period;
}

/// Bir ayın toplamları.
@immutable
class MonthTotals {
  const MonthTotals({
    required this.revenue,
    required this.businessExpense,
    required this.personalExpense,
    this.paymentCount = 0,
    this.expenseCount = 0,
  });

  static const MonthTotals empty = MonthTotals(
    revenue: Money.zero,
    businessExpense: Money.zero,
    personalExpense: Money.zero,
  );

  /// Tahsilat (gelir).
  final Money revenue;

  /// İşletme gideri = dukkan + genel.
  final Money businessExpense;

  /// Kişisel (ev) gider: kâra dahil değil.
  final Money personalExpense;
  final int paymentCount;
  final int expenseCount;

  /// İşletme kârı (ev giderleri HARİÇ).
  Money get profit => revenue - businessExpense;

  /// Eski "hepsi dahil" görünüm (bilgi amaçlı).
  Money get profitInclPersonal => profit - personalExpense;

  bool get hasData => paymentCount > 0 || expenseCount > 0;

  /// Kâr marjı yüzdesi (tam sayı, yarım yukarı); gelir yoksa null.
  int? get marginPercent {
    if (!revenue.isPositive) return null;
    final r = (profit.kurus.abs() * 200 + revenue.kurus) ~/ (revenue.kurus * 2);
    return profit.isNegative ? -r : r;
  }
}

/// Gider kapsamına göre toplamlar. Ev kâra dahil değildir; dükkan + işletme işletme giderdir.
@immutable
class ScopeBreakdown {
  const ScopeBreakdown({
    required this.home,
    required this.shop,
    required this.business,
  });
  final Money home;
  final Money shop;
  final Money business;

  Money get businessTotal => shop + business;
}

/// Bir sahibin (kullanıcı) tahsilat toplamı.
@immutable
class OwnerTotal {
  const OwnerTotal({
    required this.ownerId,
    required this.total,
    required this.count,
  });

  /// null: sahibi belirtilmemiş kayıtlar.
  final String? ownerId;
  final Money total;
  final int count;
}

/// Grafikte bir ay.
@immutable
class ChartMonth {
  const ChartMonth({
    required this.month,
    required this.revenue,
    required this.expense,
    required this.hasData,
  });
  final YearMonth month;
  final Money revenue;

  /// İşletme gideri (kişisel hariç).
  final Money expense;
  final bool hasData;
  Money get net => revenue - expense;
}

/// Alacak satırı (projenin kalan bakiyesi).
@immutable
class Receivable {
  const Receivable({required this.project, required this.overdueDays});
  final ProjectRef project;

  /// Vadesi (şimdilik teslim/bitiş tarihi) geçtiyse kaç gün; geçmediyse 0.
  final int overdueDays;
  bool get isOverdue => overdueDays > 0;
  Money get remaining => project.remaining;
}

abstract final class FinanceCalc {
  /// Grafik penceresi üst sınırı (mobil okunabilirlik).
  static const int maxChartMonths = 6;

  static DateTime? _paymentDate(Payment p) => p.paidAt;

  static MonthTotals totalsFor(
    Iterable<Payment> payments,
    Iterable<Expense> expenses,
    YearMonth month,
  ) => totalsForRange(payments, expenses, month.range);

  /// Serbest aralık ([range] başlangıç dahil, bitiş hariç) toplamları.
  static MonthTotals totalsForRange(
    Iterable<Payment> payments,
    Iterable<Expense> expenses,
    InstantRange r,
  ) {
    var revenue = Money.zero;
    var business = Money.zero;
    var personal = Money.zero;
    var pc = 0, ec = 0;
    for (final p in payments) {
      final d = _paymentDate(p);
      if (d != null && r.contains(d)) {
        revenue += p.amount;
        pc++;
      }
    }
    for (final e in expenses) {
      final d = e.date;
      if (d != null && r.contains(d)) {
        if (e.isPersonal) {
          personal += e.amount;
        } else {
          business += e.amount;
        }
        ec++;
      }
    }
    return MonthTotals(
      revenue: revenue,
      businessExpense: business,
      personalExpense: personal,
      paymentCount: pc,
      expenseCount: ec,
    );
  }

  /// Aralıktaki giderlerin kapsama göre dağılımı (Ev / Dükkan / İşletme).
  static ScopeBreakdown breakdownForRange(
    Iterable<Expense> expenses,
    InstantRange r,
  ) {
    var home = Money.zero, shop = Money.zero, business = Money.zero;
    for (final e in expenses) {
      final d = e.date;
      if (d == null || !r.contains(d)) continue;
      switch (e.scope) {
        case ScopeView.personal:
          home += e.amount;
        case ScopeView.business:
          shop += e.amount;
        case ScopeView.general:
          business += e.amount;
      }
    }
    return ScopeBreakdown(home: home, shop: shop, business: business);
  }

  /// "Kim ne kadar aldı": ödemeleri sahibine ([Payment.ownerId]) göre toplar (büyükten küçüğe).
  /// Sahibi olmayan kayıtlar `ownerId: null` altında toplanır.
  static List<OwnerTotal> byOwner(Iterable<Payment> payments) {
    final sums = <String?, Money>{};
    final counts = <String?, int>{};
    for (final p in payments) {
      final k = (p.ownerId ?? '').isEmpty ? null : p.ownerId;
      sums[k] = (sums[k] ?? Money.zero) + p.amount;
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final out = [
      for (final k in sums.keys)
        OwnerTotal(ownerId: k, total: sums[k]!, count: counts[k]!),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  /// [end] ayında biten, en fazla [maxChartMonths] aylık pencere (eskiden yeniye).
  static List<ChartMonth> chartWindow(
    Iterable<Payment> payments,
    Iterable<Expense> expenses,
    YearMonth end, {
    int months = maxChartMonths,
  }) {
    final n = months.clamp(1, maxChartMonths);
    final pl = payments.toList();
    final el = expenses.toList();
    return [
      for (var i = n - 1; i >= 0; i--)
        () {
          final m = end.addMonths(-i);
          final t = totalsFor(pl, el, m);
          return ChartMonth(
            month: m,
            revenue: t.revenue,
            expense: t.businessExpense,
            hasData: t.hasData,
          );
        }(),
    ];
  }

  /// Kalan bakiyesi olan projeler: vadesi geçenler önce, sonra kalan tutara göre azalan.
  static List<Receivable> receivables(
    Iterable<ProjectRef> projects, {
    DateTime? now,
  }) {
    final at = now ?? Ist.now();
    final list = <Receivable>[];
    for (final p in projects) {
      if (!p.remaining.isPositive) continue;
      var overdue = 0;
      final due = p.endDate;
      if (due != null) {
        final diff = Ist.dayDiff(due, at);
        if (diff > 0) overdue = diff;
      }
      list.add(Receivable(project: p, overdueDays: overdue));
    }
    list.sort((a, b) {
      if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
      final c = b.remaining.compareTo(a.remaining);
      if (c != 0) return c;
      return a.project.displayLabel.compareTo(b.project.displayLabel);
    });
    return list;
  }

  static Money totalReceivable(Iterable<Receivable> items) =>
      Money.sum(items.map((e) => e.remaining));

  /// Hızlı tutar önerileri (kuruş, tamsayı aritmetiği): kalanın %[percent]'i.
  static Money percentOf(Money amount, int percent) =>
      Money.fromKurus((amount.kurus * percent + 50) ~/ 100);

  /// Grafik eksen etiketi: "₺850", "₺12 bin", "₺1,2 Mn". (Ondalık virgül.)
  static String compact(Money m) {
    final k = m.kurus.abs();
    final sign = m.isNegative ? '−' : '';
    final tl = k / 100;
    String trim(double v) {
      final s = v.toStringAsFixed(1);
      return s.endsWith('.0')
          ? s.substring(0, s.length - 2)
          : s.replaceAll('.', ',');
    }

    if (tl >= 1000000) return '$sign₺${trim(tl / 1000000)} Mn';
    if (tl >= 1000) return '$sign₺${trim(tl / 1000)} bin';
    return '$sign₺${tl.round()}';
  }
}
