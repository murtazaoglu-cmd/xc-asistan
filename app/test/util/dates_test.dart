import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/core/util/formatters.dart';

void main() {
  // 20 Kas 2026 Cuma. 23:30 UTC = 21 Kas 02:30 İstanbul (gün kayması testi).
  final lateUtc = DateTime.utc(2026, 11, 20, 23, 30);
  final noonUtc = DateTime.utc(2026, 11, 20, 9, 0); // 12:00 İstanbul

  test('wall/fromWall gidiş-dönüş (UTC+3)', () {
    final w = Ist.wall(noonUtc);
    expect([w.year, w.month, w.day, w.hour], [2026, 11, 20, 12]);
    expect(Ist.fromWall(2026, 11, 20, 12), noonUtc);
  });

  test('gün sınırları İstanbul saatine göre', () {
    final r = Ist.today(lateUtc); // İstanbul'da 21 Kas
    expect(r.start, DateTime.utc(2026, 11, 20, 21));
    expect(r.end, DateTime.utc(2026, 11, 21, 21));
    expect(r.contains(lateUtc), isTrue);
    expect(r.contains(DateTime.utc(2026, 11, 21, 21)), isFalse); // yarı açık
    expect(Ist.tomorrow(noonUtc).start, DateTime.utc(2026, 11, 20, 21));
  });

  test('hafta Pazartesi başlar', () {
    final r = Ist.weekRange(noonUtc); // Cuma
    final w = Ist.wall(r.start);
    expect(w.weekday, DateTime.monday);
    expect([w.month, w.day], [11, 16]);
    expect(r.end.difference(r.start).inDays, 7);
    // Pazar günü bir önceki Pazartesi'ye döner
    final sunday = Ist.fromWall(2026, 11, 22, 10);
    expect(Ist.wall(Ist.weekRange(sunday).start).day, 16);
  });

  test('ay aralığı yıl geçişi', () {
    final r = Ist.monthRange(Ist.fromWall(2026, 12, 15));
    expect(Ist.wall(r.start).month, 12);
    expect(Ist.wall(r.end), DateTime.utc(2027, 1, 1));
  });

  test('ayrıştırma: Z, ofset, saat dilimsiz → İstanbul', () {
    expect(
      Ist.tryParse('2026-11-20T16:11:10.577Z'),
      DateTime.utc(2026, 11, 20, 16, 11, 10, 577),
    );
    expect(
      Ist.tryParse('2026-11-21T09:00:00+03:00'),
      DateTime.utc(2026, 11, 21, 6),
    );
    expect(Ist.tryParse('2026-11-21T09:00:00'), DateTime.utc(2026, 11, 21, 6));
    expect(Ist.tryParse('2026-11-21'), DateTime.utc(2026, 11, 20, 21));
    expect(Ist.tryParse(''), isNull);
    expect(Ist.tryParse(null), isNull);
    expect(Ist.tryParse('bozuk'), isNull);
  });

  test('gönderim biçimi ofsetli ISO ve öğlen kuralı', () {
    expect(
      Ist.toApiIso(DateTime.utc(2026, 11, 21, 6)),
      '2026-11-21T09:00:00+03:00',
    );
    // 23:30 UTC aslında İstanbul'da 21 Kas: öğlen 21 Kas 12:00
    expect(Ist.noonIso(lateUtc), '2026-11-21T12:00:00+03:00');
  });

  test('göreli gün etiketleri', () {
    expect(Ist.relativeDayLabel(noonUtc, noonUtc), 'Bugün');
    expect(
      Ist.relativeDayLabel(noonUtc.add(const Duration(days: 1)), noonUtc),
      'Yarın',
    );
    expect(
      Ist.relativeDayLabel(noonUtc.subtract(const Duration(days: 1)), noonUtc),
      'Dün',
    );
    expect(
      Ist.relativeDayLabel(noonUtc.add(const Duration(days: 5)), noonUtc),
      isNull,
    );
  });

  test('biçimler: 20 Kas 2026, saat 24', () {
    expect(Fmt.date(noonUtc), '20 Kas 2026');
    expect(Fmt.time(DateTime.utc(2026, 11, 20, 11, 5)), '14:05');
    expect(
      Fmt.dateTime(DateTime.utc(2026, 11, 20, 21, 30)),
      '21 Kas 2026, 00:30',
    );
    expect(Fmt.dateWithWeekday(noonUtc), '20 Kas 2026, Cum');
    expect(Fmt.dayHeading(noonUtc), 'Cuma 20 Kasım');
    expect(Fmt.relativeDateTime(noonUtc, noonUtc), 'Bugün 12:00');
  });
}
