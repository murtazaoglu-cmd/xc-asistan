// Para grafiği veri dönüştürücüsü (saf mantık; testlenir).
//   - Aylık: bugünden geriye 12 ay SÜREKLİ pencere (eksik ay → boş çubuk grubu),
//     ekranda en fazla 6 ay görünür, geçmiş yatay kaydırmayla.
//   - İki seri: Gelir ve Gider(işletme). Ev giderleri grafikte YOK (kâr dışı, ayrı satır).
//   - Eksen etiketleri kısa: ay adı ("Kas") + yıl yalnız ocakta/ilk çubukta; para "₺12 B".
import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/formatters.dart';
import '../../../core/util/money.dart';
import 'report_models.dart';

/// Kısa para biçimi: ₺850 · ₺1,5 B · ₺12 B · ₺120 B · ₺1,2 Mn · ₺3 Mr (B = bin).
abstract final class CompactMoney {
  static String format(Money m, {bool symbol = true}) {
    final neg = m.kurus < 0;
    final abs = m.kurus.abs() / 100; // yalnız gösterim
    final cur = symbol ? '₺' : '';
    final sign = neg ? '−' : '';
    if (abs.roundToDouble() < 1000) {
      return '$sign$cur${_num(abs.roundToDouble())}';
    }
    const units = [('B', 1e3), ('Mn', 1e6), ('Mr', 1e9)];
    var idx = 0;
    while (idx < units.length - 1 && abs >= units[idx + 1].$2) {
      idx++;
    }
    var v = abs / units[idx].$2;
    var s = _round(v);
    // 999,96 B → "1000" olmasın; bir üst birime geç.
    if (double.parse(s.replaceAll(',', '.')) >= 1000 &&
        idx < units.length - 1) {
      idx++;
      v = abs / units[idx].$2;
      s = _round(v);
    }
    return '$sign$cur$s ${units[idx].$1}';
  }

  static String _round(double v) =>
      v < 100 ? _num((v * 10).roundToDouble() / 10) : _num(v.roundToDouble());

  static String _num(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1).replaceAll('.', ',');
  }
}

/// Y ekseni ölçeği: [ticks] eşit aralık, "güzel" adım (1, 2, 2,5, 5 × 10^k).
@immutable
class ChartScale {
  const ChartScale(this.max, this.step, this.ticks);
  final double max;
  final double step;
  final int ticks;

  static ChartScale nice(double maxValue, {int ticks = 4}) {
    if (!maxValue.isFinite || maxValue <= 0)
      return ChartScale(ticks * 250.0, 250, ticks);
    final raw = maxValue / ticks;
    var mag = 1.0;
    while (mag * 10 <= raw) {
      mag *= 10;
    }
    while (mag > raw) {
      mag /= 10;
    }
    final norm = raw / mag;
    final f = norm <= 1
        ? 1
        : (norm <= 2 ? 2 : (norm <= 2.5 ? 2.5 : (norm <= 5 ? 5 : 10)));
    final step = f * mag;
    return ChartScale(step * ticks, step, ticks);
  }

  List<double> get tickValues => [for (var i = 0; i <= ticks; i++) step * i];
}

@immutable
class ChartBar {
  const ChartBar({
    required this.key,
    required this.year,
    required this.month,
    required this.label,
    this.yearLabel,
    this.revenue = Money.zero,
    this.expense = Money.zero,
    this.homeExpense = Money.zero,
    this.net = Money.zero,
    this.netInclHome = Money.zero,
    this.hasData = false,
  });

  final String key;
  final int year;
  final int? month;

  /// Eksen etiketi: "Kas" (aylık) / "2026" (yıllık).
  final String label;

  /// Yıl ipucu (ocak ayında ve ilk çubukta): "2026". Yıllıkta null.
  final String? yearLabel;
  final Money revenue;

  /// İşletme gideri (dukkan + genel). Ev gideri DEĞİL.
  final Money expense;
  final Money homeExpense;

  /// İşletme net kârı = gelir − işletme gideri.
  final Money net;
  final Money netInclHome;

  /// Dönemde en az bir hareket var mı (yoksa "Bu ay kayıt yok").
  final bool hasData;

  /// "Kasım 2026" / "2026".
  String get longLabel =>
      month == null ? '$year' : '${Fmt.monthsLong[month! - 1]} $year';
}

@immutable
class MoneyChartData {
  const MoneyChartData(this.bars, {this.visibleCount = 6});

  /// Eskiden yeniye sıralı, sürekli.
  final List<ChartBar> bars;

  /// Ekranda aynı anda görünen çubuk grubu sayısı (kalanı kaydırmayla).
  final int visibleCount;

  /// Kaydırmadan ilk görünen (en yeni) pencere.
  List<ChartBar> get visibleBars => bars.length <= visibleCount
      ? bars
      : bars.sublist(bars.length - visibleCount);

  bool get hasAnyData => bars.any((b) => b.hasData);

  /// Başlangıç seçimi: verisi olan en yeni dönem (yoksa son).
  int get defaultSelected {
    for (var i = bars.length - 1; i >= 0; i--) {
      if (bars[i].hasData) return i;
    }
    return bars.isEmpty ? 0 : bars.length - 1;
  }

  /// Ekranda ilk açıldığında görünen (en yeni) [visibleCount] çubuğun toplamı.
  ({Money revenue, Money expense}) visibleTotals() {
    final from = (bars.length - visibleCount).clamp(0, bars.length);
    var r = Money.zero, e = Money.zero;
    for (final b in bars.skip(from)) {
      r += b.revenue;
      e += b.expense;
    }
    return (revenue: r, expense: e);
  }

  /// Aylık: [now] ayında biten [months] aylık sürekli pencere. Pencere dışı noktalar atılır;
  /// eksik ayların çubuğu boştur ve `hasData=false` (sıfır tutar yazılmaz).
  static MoneyChartData monthly(
    List<ProfitPoint> points, {
    required DateTime now,
    int months = 12,
    int visible = 6,
  }) {
    final w = Ist.wall(now);
    final endOrd = w.year * 12 + w.month - 1;
    final byOrd = _index(points);
    final bars = <ChartBar>[];
    for (var i = months - 1; i >= 0; i--) {
      final ord = endOrd - i;
      final year = ord ~/ 12;
      final month = ord % 12 + 1;
      final p = byOrd[ord];
      bars.add(
        _bar(
          p,
          key: '$year-${month.toString().padLeft(2, '0')}',
          year: year,
          month: month,
          label: Fmt.monthsShort[month - 1],
          yearLabel: (month == 1 || i == months - 1) ? '$year' : null,
        ),
      );
    }
    return MoneyChartData(bars, visibleCount: visible);
  }

  /// Yıllık: [now] yılında biten [years] yıl.
  static MoneyChartData yearly(
    List<ProfitPoint> points, {
    required DateTime now,
    int years = 5,
    int visible = 6,
  }) {
    final endYear = Ist.wall(now).year;
    final byOrd = _index(points);
    final bars = <ChartBar>[
      for (var y = endYear - years + 1; y <= endYear; y++)
        _bar(byOrd[y], key: '$y', year: y, month: null, label: '$y'),
    ];
    return MoneyChartData(bars, visibleCount: visible);
  }

  static Map<int, ProfitPoint> _index(List<ProfitPoint> points) {
    final m = <int, ProfitPoint>{};
    for (final p in points) {
      final per = p.parsed;
      if (per != null) m[per.ordinal] = p; // aynı dönem iki kez gelirse sonuncu
    }
    return m;
  }

  static ChartBar _bar(
    ProfitPoint? p, {
    required String key,
    required int year,
    required int? month,
    required String label,
    String? yearLabel,
  }) {
    if (p == null) {
      return ChartBar(
        key: key,
        year: year,
        month: month,
        label: label,
        yearLabel: yearLabel,
      );
    }
    return ChartBar(
      key: key,
      year: year,
      month: month,
      label: label,
      yearLabel: yearLabel,
      revenue: p.revenue,
      expense: p.businessExpenses,
      homeExpense: p.homeExpenses,
      net: p.netProfit,
      netInclHome: p.netProfitInclHome,
      hasData: !p.isEmpty,
    );
  }
}
