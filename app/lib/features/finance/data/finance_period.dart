// Seçili dönem: bir takvim ayı ya da serbest tarih aralığı (başlangıç + bitiş GÜN DAHİL, İstanbul günü).
// Özet, Ödemeler ve Giderler sekmeleri aynı dönemi kullanır.
import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/formatters.dart';
import 'finance_calc.dart';

@immutable
class FinancePeriod {
  const FinancePeriod._({
    required this.range,
    required this.label,
    required this.endMonth,
    required this.isCustom,
    this.startDay,
    this.endDay,
  });

  /// [başlangıç, bitiş) İstanbul sınırları.
  final InstantRange range;

  /// "Kasım 2026" ya da "1 Kas – 15 Kas 2026".
  final String label;

  /// Grafik penceresinin bittiği ay (aralığın bitiş ayı).
  final YearMonth endMonth;
  final bool isCustom;

  /// Serbest aralıkta seçilen günler (İstanbul gün başlangıcı).
  final DateTime? startDay;
  final DateTime? endDay;

  factory FinancePeriod.month(YearMonth m) => FinancePeriod._(
    range: m.range,
    label: m.label,
    endMonth: m,
    isCustom: false,
  );

  /// [start] ve [end] aynı gün de olabilir; sıra ters verilirse düzeltilir. Bitiş günü DAHİLDİR.
  factory FinancePeriod.custom(DateTime start, DateTime end) {
    var a = Ist.wall(start);
    var b = Ist.wall(end);
    if (b.isBefore(a)) {
      final t = a;
      a = b;
      b = t;
    }
    final s = Ist.fromWall(a.year, a.month, a.day);
    final e = Ist.fromWall(b.year, b.month, b.day + 1);
    final sameYear = a.year == b.year;
    final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
    String d(DateTime w, {bool year = false}) =>
        '${w.day} ${Fmt.monthsShort[w.month - 1]}${year ? ' ${w.year}' : ''}';
    final label = sameDay
        ? d(b, year: true)
        : '${d(a, year: !sameYear)} – ${d(b, year: true)}';
    return FinancePeriod._(
      range: InstantRange(s, e),
      label: label,
      endMonth: YearMonth(b.year, b.month),
      isCustom: true,
      startDay: s,
      endDay: Ist.fromWall(b.year, b.month, b.day),
    );
  }

  bool contains(DateTime? instant) =>
      instant != null && range.contains(instant);

  @override
  bool operator ==(Object other) =>
      other is FinancePeriod &&
      other.range.start == range.start &&
      other.range.end == range.end;

  @override
  int get hashCode => Object.hash(range.start, range.end);
}
