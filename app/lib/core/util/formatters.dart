// Gösterim biçimleri (tr_TR). Elle yazılmış Türkçe ay/gün adları: intl tarih
// verisi yüklü olmasa da (testler dahil) aynı çıktıyı verir.
import 'dates.dart';

abstract final class Fmt {
  static const List<String> monthsShort = [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];
  static const List<String> weekdaysShort = [
    'Pzt',
    'Sal',
    'Çar',
    'Per',
    'Cum',
    'Cmt',
    'Paz',
  ];
  static const List<String> weekdaysLong = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  static const List<String> monthsLong = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// "20 Kas 2026" (İstanbul günü)
  static String date(DateTime instant) {
    final w = Ist.wall(instant);
    return '${w.day} ${monthsShort[w.month - 1]} ${w.year}';
  }

  /// "14:30" (24 saat, İstanbul)
  static String time(DateTime instant) {
    final w = Ist.wall(instant);
    return '${_two(w.hour)}:${_two(w.minute)}';
  }

  /// "20 Kas 2026, 14:30"
  static String dateTime(DateTime instant) =>
      '${date(instant)}, ${time(instant)}';

  /// "20 Kas 2026, Cum"
  static String dateWithWeekday(DateTime instant) {
    final w = Ist.wall(instant);
    return '${date(instant)}, ${weekdaysShort[w.weekday - 1]}';
  }

  /// "Cuma 20 Kasım" (başlıklar için)
  static String dayHeading(DateTime instant) {
    final w = Ist.wall(instant);
    return '${weekdaysLong[w.weekday - 1]} ${w.day} ${monthsLong[w.month - 1]}';
  }

  /// "Bugün 14:30", "Yarın 09:00", "Dün 18:00"; diğer günlerde "20 Kas 2026, 14:30".
  static String relativeDateTime(DateTime instant, [DateTime? now]) {
    final rel = Ist.relativeDayLabel(instant, now);
    return rel != null ? '$rel ${time(instant)}' : dateTime(instant);
  }

  /// "Bugün", "Yarın", "Dün" ya da "20 Kas 2026".
  static String relativeDate(DateTime instant, [DateTime? now]) =>
      Ist.relativeDayLabel(instant, now) ?? date(instant);
}
