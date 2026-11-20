import 'package:material_ui/material_ui.dart';

import '../util/formatters.dart';

enum DateTextMode {
  /// 20 Kas 2026
  date,

  /// 20 Kas 2026, 14:30
  dateTime,

  /// 14:30
  time,

  /// 20 Kas 2026, Cum
  dateWeekday,

  /// Bugün 14:30 / Yarın 09:00 / 20 Kas 2026, 14:30
  relativeDateTime,

  /// Bugün / Yarın / 20 Kas 2026
  relativeDate,
}

/// Tarih/saat gösterimi (İstanbul saati, saat 24'lük). Değer yoksa [placeholder].
class DateText extends StatelessWidget {
  const DateText(
    this.date, {
    super.key,
    this.mode = DateTextMode.date,
    this.style,
    this.placeholder = '-',
  });

  final DateTime? date;
  final DateTextMode mode;
  final TextStyle? style;
  final String placeholder;

  static String format(
    DateTime? d,
    DateTextMode mode, {
    String placeholder = '-',
  }) {
    if (d == null) return placeholder;
    switch (mode) {
      case DateTextMode.date:
        return Fmt.date(d);
      case DateTextMode.dateTime:
        return Fmt.dateTime(d);
      case DateTextMode.time:
        return Fmt.time(d);
      case DateTextMode.dateWeekday:
        return Fmt.dateWithWeekday(d);
      case DateTextMode.relativeDateTime:
        return Fmt.relativeDateTime(d);
      case DateTextMode.relativeDate:
        return Fmt.relativeDate(d);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Text(format(date, mode, placeholder: placeholder), style: style);
}
