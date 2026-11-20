// Tarih/saat kuralları (sözleşme §0): yanıtlar UTC ISO-8601; gün sınırları
// (bugün/yarın/hafta/ay) İSTANBUL saatine göredir. Europe/Istanbul yaz saati
// uygulamaz (sabit UTC+3), bu yüzden sabit ofset güvenle kullanılır.
//
// "Duvar saati" (wall): İstanbul'daki saat bileşenlerini taşıyan, UTC işaretli
// bir DateTime. Yalnızca biçimlendirme/bileşen okuma içindir; karşılaştırma ve
// saklama için gerçek anı (UTC DateTime) kullanın.
import 'package:flutter/foundation.dart';

/// Yarı açık zaman aralığı: [start, end).
@immutable
class InstantRange {
  const InstantRange(this.start, this.end);
  final DateTime start;
  final DateTime end;

  bool contains(DateTime instant) =>
      !instant.isBefore(start) && instant.isBefore(end);

  @override
  bool operator ==(Object other) =>
      other is InstantRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'InstantRange($start, $end)';
}

abstract final class Ist {
  static const Duration offset = Duration(hours: 3);

  /// Testlerde saati sabitlemek için değiştirilebilir.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Şu an (UTC an).
  static DateTime now() => clock().toUtc();

  /// Gerçek an → İstanbul duvar saati (UTC işaretli).
  static DateTime wall(DateTime instant) => instant.toUtc().add(offset);

  /// İstanbul duvar saati bileşenleri → gerçek an (UTC).
  static DateTime fromWall(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
    int second = 0,
  ]) => DateTime.utc(year, month, day, hour, minute, second).subtract(offset);

  /// İstanbul gününün başlangıcı (00:00).
  static DateTime startOfDay(DateTime instant) {
    final w = wall(instant);
    return fromWall(w.year, w.month, w.day);
  }

  /// İstanbul günü [start, ertesi gün 00:00). [days]: bugünden kaç gün ileri (negatif geri).
  static InstantRange dayRange([DateTime? instant, int days = 0]) {
    final w = wall(instant ?? now());
    final start = fromWall(w.year, w.month, w.day + days);
    final end = fromWall(w.year, w.month, w.day + days + 1);
    return InstantRange(start, end);
  }

  static InstantRange today([DateTime? instant]) => dayRange(instant);
  static InstantRange tomorrow([DateTime? instant]) => dayRange(instant, 1);

  /// Hafta Pazartesi başlar (sözleşme §2).
  static InstantRange weekRange([DateTime? instant]) {
    final w = wall(instant ?? now());
    final back = w.weekday - DateTime.monday; // Pzt=1
    final start = fromWall(w.year, w.month, w.day - back);
    final end = fromWall(w.year, w.month, w.day - back + 7);
    return InstantRange(start, end);
  }

  static InstantRange monthRange([DateTime? instant]) {
    final w = wall(instant ?? now());
    return InstantRange(
      fromWall(w.year, w.month, 1),
      fromWall(w.year, w.month + 1, 1),
    );
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      startOfDay(a) == startOfDay(b);

  /// İstanbul takvim günü farkı: (b'nin günü) - (a'nın günü).
  static int dayDiff(DateTime a, DateTime b) =>
      startOfDay(b).difference(startOfDay(a)).inDays;

  static final RegExp _hasZone = RegExp(r'(Z|[+-]\d{2}(:?\d{2})?)$');

  /// ISO-8601 → UTC an. Saat dilimi yoksa İstanbul duvar saati varsayılır. Çözülemezse null.
  static DateTime? tryParse(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    // Yalnız tarih ("2026-11-20") ya da saat dilimsiz ISO → İstanbul duvar saati.
    final hasTime = t.contains('T') || t.contains(' ');
    final hasZone = hasTime && _hasZone.hasMatch(t);
    if (!hasZone) {
      final p = DateTime.tryParse(t);
      if (p == null) return null;
      return fromWall(p.year, p.month, p.day, p.hour, p.minute, p.second);
    }
    return DateTime.tryParse(t)?.toUtc();
  }

  /// Sunucuya gönderim: İstanbul ofsetli ISO ("2026-11-21T09:00:00+03:00").
  static String toApiIso(DateTime instant) {
    final w = wall(instant);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${w.year.toString().padLeft(4, '0')}-${two(w.month)}-${two(w.day)}'
        'T${two(w.hour)}:${two(w.minute)}:${two(w.second)}+03:00';
  }

  /// Panel kuralı: ödeme/gider/proje tarihleri öğlen 12:00 İstanbul saatiyle gönderilir
  /// (UTC gün kaymasını önler). [anyInstant] hangi İstanbul gününe ait olduğunu belirler.
  static String noonIso(DateTime anyInstant) {
    final w = wall(anyInstant);
    return toApiIso(fromWall(w.year, w.month, w.day, 12));
  }

  /// "Bugün" / "Yarın" / "Dün" ya da null.
  static String? relativeDayLabel(DateTime instant, [DateTime? now]) {
    final d = dayDiff(now ?? Ist.now(), instant);
    switch (d) {
      case 0:
        return 'Bugün';
      case 1:
        return 'Yarın';
      case -1:
        return 'Dün';
      default:
        return null;
    }
  }
}
