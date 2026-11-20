import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/features/appointments/data/appointment_logic.dart';
import 'package:xc_asistan/features/appointments/data/appointment_models.dart';
import 'package:xc_asistan/features/appointments/data/tr_text.dart';

Appointment appt(
  String id,
  DateTime at, {
  String status = 'beklemede',
  String? who = 'u1',
}) => Appointment(
  id: id,
  type: 'Montaj',
  scheduledAt: at,
  status: status,
  assignedUserId: who,
);

void main() {
  final t = Ist.fromWall(2026, 11, 20, 14);

  group('findConflicts', () {
    test('aynı kişi + 60 dk içinde → çakışma', () {
      final c = findConflicts(
        [
          appt('a', Ist.fromWall(2026, 11, 20, 14, 30)),
          appt('b', Ist.fromWall(2026, 11, 20, 13, 1)),
          appt('c', Ist.fromWall(2026, 11, 20, 15)),
        ],
        at: t,
        assigneeId: 'u1',
      );
      expect(c.map((e) => e.id), ['a', 'b']);
    });

    test('başka kişi, tamamlanmış, iptal ve kendisi sayılmaz', () {
      final c = findConflicts(
        [
          appt('a', t, who: 'u2'),
          appt('b', t, status: 'tamamlandı'),
          appt('c', t, status: 'iptal'),
          appt('self', t),
        ],
        at: t,
        assigneeId: 'u1',
        excludeId: 'self',
      );
      expect(c, isEmpty);
    });

    test('atanan yoksa çakışma aranmaz', () {
      expect(findConflicts([appt('a', t)], at: t, assigneeId: null), isEmpty);
    });
  });

  group('takvim', () {
    test('weekDays Pazartesi başlar, 7 gün', () {
      final days = weekDays(Ist.fromWall(2026, 11, 20, 14)); // Cuma
      expect(days, hasLength(7));
      expect(Ist.wall(days.first).day, 16); // Pzt 16 Kas
      expect(Ist.wall(days.last).day, 22);
      expect(Ist.wall(days.first).weekday, DateTime.monday);
    });

    test('monthGridRange 7 günün katı ve ayı kapsar', () {
      final r = monthGridRange(Ist.fromWall(2026, 11, 20));
      final n = Ist.dayDiff(r.start, r.end);
      expect(n % 7, 0);
      expect(r.contains(Ist.fromWall(2026, 11, 1)), isTrue);
      expect(r.contains(Ist.fromWall(2026, 11, 30, 23)), isTrue);
      expect(Ist.wall(r.start).weekday, DateTime.monday);
      // Kas 2026: 1 Kas Pazar → ızgara 26 Eki Pazartesi'den başlar, 6 hafta.
      expect(Ist.wall(r.start).month, 10);
      expect(n, 42);
      expect(monthGridDays(Ist.fromWall(2026, 11, 20)), hasLength(42));
    });

    test('şubat 4 hafta (Pzt başlangıçlı ay) 28 gün olabilir', () {
      // Şubat 2027: 1 Şub Pazartesi, 28 gün → tam 4 hafta
      final r = monthGridRange(Ist.fromWall(2027, 2, 10));
      expect(Ist.dayDiff(r.start, r.end), 28);
    });

    test('groupByDay İstanbul gününe göre gruplar (gece yarısı sınırı)', () {
      final late = Ist.fromWall(2026, 11, 20, 23, 30);
      final early = Ist.fromWall(2026, 11, 21, 0, 15);
      final g = groupByDay([appt('a', late), appt('b', early)]);
      expect(g.length, 2);
      expect(g[Ist.fromWall(2026, 11, 20)]!.single.id, 'a');
      expect(g[Ist.fromWall(2026, 11, 21)]!.single.id, 'b');
    });
  });

  group('snoozeOptions', () {
    test('1 saat, yarın aynı saat, gelecek hafta', () {
      final o = snoozeOptions(t, Ist.fromWall(2026, 11, 20, 9));
      expect(o[0].at, t.add(const Duration(hours: 1)));
      expect(o[1].at, Ist.fromWall(2026, 11, 21, 14));
      expect(o[2].at, Ist.fromWall(2026, 11, 27, 14));
    });

    test('geçmiş randevuda "1 saat sonra" şimdiden sayılır', () {
      final now = Ist.fromWall(2026, 11, 20, 16);
      final o = snoozeOptions(t, now);
      expect(o[0].at, now.add(const Duration(hours: 1)));
    });
  });

  group('validateAppointmentForm', () {
    AppointmentFormErrors v({
      String type = 'Keşif',
      DateTime? at,
      bool link = false,
      String name = 'Ayşe',
      String phone = '',
      String address = '',
      String notes = '',
      bool restricted = false,
    }) => validateAppointmentForm(
      type: type,
      scheduledAt: at ?? t,
      hasLink: link,
      customerName: name,
      customerPhone: phone,
      address: address,
      notes: notes,
      restricted: restricted,
    );

    test('geçerli form', () => expect(v().isValid, isTrue));
    test('tür zorunlu ve ≤40', () {
      expect(v(type: ' ')['type'], isNotNull);
      expect(v(type: 'x' * 41)['type'], isNotNull);
      expect(v(type: 'x' * 40).isValid, isTrue);
    });
    test('tarih zorunlu', () {
      final e = validateAppointmentForm(
        type: 'Keşif',
        scheduledAt: null,
        hasLink: false,
        customerName: 'a',
        customerPhone: '',
        address: '',
        notes: '',
      );
      expect(e['scheduledAt'], 'Tarih ve saat seçin.');
    });
    test('müşteri: bağlantı ya da ad gerekir', () {
      expect(v(name: '')['customer'], isNotNull);
      expect(v(name: '', link: true).isValid, isTrue);
    });
    test('telefon biçimi', () {
      expect(v(phone: '123')['phone'], isNotNull);
      expect(v(phone: '0532 111 22 33').isValid, isTrue);
      expect(v(phone: '+90 532 111 22 33').isValid, isTrue);
    });
    test('adres ≤500, not ≤1000', () {
      expect(v(address: 'a' * 501)['address'], isNotNull);
      expect(v(notes: 'n' * 1001)['notes'], isNotNull);
    });
    test('saha (restricted) yalnız tarih ve notu denetler', () {
      final e = v(type: '', name: '', phone: 'x', restricted: true);
      expect(e.isValid, isTrue);
    });
  });

  test('trLower/trCapitalize Türkçe harfleri doğru çevirir', () {
    expect(trLower('İşler'), 'işler');
    expect(trLower('IRMAK'), 'ırmak');
    expect(trLower('Fiyat teklifi'), 'fiyat teklifi');
    expect(trCapitalize('iş'), 'İş');
    expect(trCapitalize('ırmak'), 'Irmak');
    expect(trCapitalize(''), '');
  });
}
