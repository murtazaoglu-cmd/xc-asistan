import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/features/appointments/data/appointment_models.dart';

/// Sözleşme §9 "çözümlenmiş randevu" örneği.
Map<String, dynamic> sample() => {
  'id': 'a1',
  'offer_id': 'o1',
  'project_id': null,
  'type': 'Keşif',
  'scheduled_at': '2026-11-20T16:41:10.435Z',
  'assigned_user_id': 'u-saha',
  'assigned_user_name': 'Saha1',
  'notes': null,
  'status': 'beklemede',
  'owner_id': 'u-admin',
  'customer_name': 'Ayşe Yılmaz',
  'customer_phone': '0532 111 22 33',
  'address': 'Konacık Mah. 12 Sok.',
  'lat': 37.0344,
  'lng': 27.4305,
  'service': 'Pergola',
  'offer_code': 'OFR-1001',
  'project_code': null,
  'offer_name': 'Ayşe Yılmaz',
  'offer_phone': '0532 111 22 33',
  'offer_service': 'Pergola',
  'project_customer': null,
};

void main() {
  group('Appointment.fromJson', () {
    test('sözleşme örneğini birebir okur', () {
      final a = Appointment.fromJson(sample());
      expect(a.id, 'a1');
      expect(a.type, 'Keşif');
      expect(a.scheduledAt, DateTime.utc(2026, 11, 20, 16, 41, 10, 435));
      expect(a.status, 'beklemede');
      expect(a.assignedUserName, 'Saha1');
      expect(a.lat, 37.0344);
      expect(a.offerCode, 'OFR-1001');
      expect(a.notes, isNull);
      expect(a.hasLink, isTrue);
      expect(a.isOpen, isTrue);
    });

    test('boş/eksik/yanlış tipli alanlarda çökmez', () {
      final a = Appointment.fromJson({
        'id': 5,
        'scheduled_at': 'bozuk',
        'lat': 'x',
        'notes': '   ',
      });
      expect(a.id, '5');
      expect(a.scheduledAt, isNull);
      expect(a.type, '');
      expect(a.status, '');
      expect(a.lat, isNull);
      expect(a.notes, isNull);
      expect(Appointment.fromJson(const {}).id, '');
    });

    test('ad/telefon/hizmet yedek zinciri', () {
      final a = Appointment.fromJson({
        'id': 'x',
        'type': 'Montaj',
        'status': 'beklemede',
        'offer_name': 'Teklif Adı',
        'offer_phone': '0533',
        'offer_service': 'Cam',
        'project_customer': 'Proje Müşterisi',
      });
      expect(a.displayName, 'Teklif Adı');
      expect(a.displayPhone, '0533');
      expect(a.displayService, 'Cam');
      final b = Appointment.fromJson({'id': 'y', 'project_customer': 'PM'});
      expect(b.displayName, 'PM');
    });

    test('durum yardımcıları panel ve eski değerleri tanır', () {
      Appointment s(String st) =>
          Appointment.fromJson({'id': '1', 'status': st});
      expect(s('tamamlandı').isDone, isTrue);
      expect(s('tamamlandi').isDone, isTrue);
      expect(s('iptal edildi').isCancelled, isTrue);
      expect(s('planlandi').isOpen, isTrue);
      expect(s('bilinmeyen').isOpen, isTrue);
      expect(s('iptal').isOpen, isFalse);
    });

    test('isOverdue: yalnız açık ve geçmiş', () {
      final now = DateTime.utc(2026, 11, 20, 12);
      Appointment at(String st, DateTime t) => Appointment.fromJson({
        'id': '1',
        'status': st,
        'scheduled_at': t.toIso8601String(),
      });
      expect(
        at('beklemede', DateTime.utc(2026, 11, 20, 9)).isOverdue(now),
        isTrue,
      );
      expect(
        at('beklemede', DateTime.utc(2026, 11, 20, 15)).isOverdue(now),
        isFalse,
      );
      expect(
        at('tamamlandı', DateTime.utc(2026, 11, 20, 9)).isOverdue(now),
        isFalse,
      );
    });

    test('copyWith yalnız istenen alanı değiştirir', () {
      final a = Appointment.fromJson(sample());
      final b = a.copyWith(status: 'tamamlandı');
      expect(b.status, 'tamamlandı');
      expect(b.customerName, a.customerName);
      expect(b.scheduledAt, a.scheduledAt);
    });
  });

  group('AppointmentDraft', () {
    final at = Ist.fromWall(2026, 11, 21, 9);

    test('POST gövdesi: İstanbul ofsetli ISO, boş alanlar yok', () {
      final d = AppointmentDraft(
        type: ' Keşif ',
        scheduledAt: at,
        notes: '  ',
        customerName: 'Ayşe',
        customerPhone: '',
        address: null,
        assignedUserId: 'u1',
      );
      expect(d.toCreateJson(), {
        'type': 'Keşif',
        'scheduled_at': '2026-11-21T09:00:00+03:00',
        'assigned_user_id': 'u1',
        'customer_name': 'Ayşe',
      });
    });

    test('POST: bağlantı kimlikleri gönderilir', () {
      final d = AppointmentDraft(
        type: 'Montaj',
        scheduledAt: at,
        offerId: 'o1',
        projectId: 'p1',
      );
      final j = d.toCreateJson();
      expect(j['offer_id'], 'o1');
      expect(j['project_id'], 'p1');
    });

    test('PATCH yalnız değişenleri gönderir', () {
      final o = Appointment.fromJson(sample());
      final same = AppointmentDraft(
        type: o.type,
        scheduledAt: o.scheduledAt!,
        offerId: o.offerId,
        assignedUserId: o.assignedUserId,
        customerName: o.displayName,
        customerPhone: o.displayPhone,
        address: o.address,
      );
      expect(same.toPatchJson(o), isEmpty);
    });

    test(
      'PATCH: bağlantı/atama kaldırılınca null, adres değişince koordinat null',
      () {
        final o = Appointment.fromJson(sample());
        final d = AppointmentDraft(
          type: 'Montaj',
          scheduledAt: at,
          offerId: null,
          assignedUserId: null,
          customerName: o.displayName,
          customerPhone: o.displayPhone,
          address: 'Yeni adres',
          notes: 'Not',
        );
        final p = d.toPatchJson(o);
        expect(p['type'], 'Montaj');
        expect(p['scheduled_at'], '2026-11-21T09:00:00+03:00');
        expect(p.containsKey('offer_id') && p['offer_id'] == null, isTrue);
        expect(
          p.containsKey('assigned_user_id') && p['assigned_user_id'] == null,
          isTrue,
        );
        expect(p['address'], 'Yeni adres');
        expect(p.containsKey('lat') && p['lat'] == null, isTrue);
        expect(p.containsKey('lng') && p['lng'] == null, isTrue);
        expect(p['notes'], 'Not');
        expect(p.containsKey('customer_name'), isFalse);
      },
    );
  });

  group('LinkCandidate', () {
    test('teklif, proje, müşteri satırlarını okur', () {
      final o = LinkCandidate.fromOffer({
        'id': 'o1',
        'code': 'OFR-1',
        'name': 'Ayşe',
        'phone': '0532',
        'service': 'Cam',
        'region': 'Bodrum',
        'address': 'Adres',
        'lat': 1.5,
        'lng': 2.5,
      });
      expect(o.kind, LinkKind.offer);
      expect(o.title, 'Ayşe');
      expect(o.subtitle, 'OFR-1 · Cam · Bodrum');
      expect(o.lat, 1.5);
      final p = LinkCandidate.fromProject({
        'id': 'p1',
        'code': 'PRJ-1',
        'customer_name': 'Ali',
        'stage': 'Üretim',
      });
      expect(p.kind, LinkKind.project);
      expect(p.subtitle, 'PRJ-1 · Üretim');
      final c = LinkCandidate.fromCustomer({
        'phone_key': '0532',
        'name': 'Veli',
        'phone': '0532 1',
      });
      expect(c.kind, LinkKind.customer);
      expect(c.id, '0532');
      expect(LinkCandidate.fromOffer(const {}).title, '-');
    });
  });
}
