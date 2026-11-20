import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/customers/data/customer_models.dart';

void main() {
  group('Customer.fromJson', () {
    test('sözleşme satırı birebir okunur', () {
      final c = Customer.fromJson({
        'phone_key': '05321112233',
        'name': 'Ayşe Yılmaz',
        'email': 'ayse@x.com',
        'phone': '0532 111 22 33',
        'region': 'Bodrum',
        'address': 'Konacık Mah.',
        'lat': 37.03,
        'lng': 27.43,
        'offer_count': 3,
        'first_contact': '2026-11-01T07:00:00.000Z',
        'last_contact': '2026-11-20T08:30:00.000Z',
        'project_count': 2,
        'total_contracted': 12000.5,
        'total_paid': '4000.25',
      });
      expect(c.phoneKey, '05321112233');
      expect(c.offerCount, 3);
      expect(c.projectCount, 2);
      expect(c.totalContracted, Money.fromKurus(1200050));
      expect(c.totalPaid, Money.fromKurus(400025));
      expect(c.remaining, Money.fromKurus(800025));
      expect(c.lastContact, DateTime.utc(2026, 11, 20, 8, 30));
      expect(c.isOfferDerived, isTrue);
    });

    test('eksik/null alanlarda çökmez; phone_key telefondan türetilir', () {
      final c = Customer.fromJson({'name': null, 'phone': '0532 111 22 33'});
      expect(c.phoneKey, '05321112233');
      expect(c.name, '');
      expect(c.displayName, '-');
      expect(c.totalContracted, Money.zero);
      expect(c.isOfferDerived, isFalse);
      expect(Customer.fromJson({}).phoneKey, '');
    });

    test('kalan bakiye negatif olmaz (fazla ödeme)', () {
      final c = Customer.fromJson({
        'phone_key': '1',
        'name': 'A',
        'total_contracted': 100,
        'total_paid': 150,
      });
      expect(c.remaining, Money.zero);
    });

    test('baş harfler Türkçe büyük harfle', () {
      expect(Customer.initialsOf('ayşe yılmaz'), 'AY');
      expect(Customer.initialsOf('ibrahim'), 'İB');
      expect(Customer.initialsOf('ışık demir'), 'ID');
      expect(Customer.initialsOf('  '), '?');
      expect(Customer.initialsOf('Ali Veli Can'), 'AC');
    });
  });

  group('CustomerHistory', () {
    test(
      'teklif toplamı quote.total ya da quote_total; proje para alanları',
      () {
        final h = CustomerHistory.fromJson({
          'offers': [
            {
              'id': 'o1',
              'code': 'OFR-1',
              'status': 'Yeni',
              'quote': {'total': 1200},
              'created_at': '2026-11-01T10:00:00Z',
            },
            {'id': 'o2', 'quote': null, 'quote_total': '300.5'},
            {'id': 'o3'},
          ],
          'projects': [
            {
              'id': 'p1',
              'code': 'PRJ-1',
              'stage': 'Montaj',
              'total_amount': 5000,
              'paid_amount': 2000,
            },
          ],
        });
        expect(h.offers[0].total, Money.fromTl(1200));
        expect(h.offers[1].total, Money.fromKurus(30050));
        expect(h.offers[2].total, isNull);
        expect(h.projects.single.remaining, Money.fromTl(3000));
      },
    );

    test('hatalı gövdede boş liste', () {
      final h = CustomerHistory.fromJson({'offers': 'x', 'projects': null});
      expect(h.offers, isEmpty);
      expect(h.projects, isEmpty);
    });
  });

  group('CustomerInput', () {
    const input = CustomerInput(
      name: '  Ayşe  ',
      phone: '0532 111 22 33',
      email: '',
      region: ' Bodrum ',
      address: '',
      note: 'Cuma evde',
    );

    test('POST gövdesi boş isteğe bağlı alanları göndermez', () {
      expect(input.toCreateJson(), {
        'name': 'Ayşe',
        'phone': '0532 111 22 33',
        'region': 'Bodrum',
        'note': 'Cuma evde',
      });
      expect(input.phoneKey, '05321112233');
    });

    test('PATCH gövdesi boş alanı null ile temizler, telefon göndermez', () {
      final j = input.toPatchJson();
      expect(j.containsKey('phone'), isFalse);
      expect(j['email'], isNull);
      expect(j['address'], isNull);
      expect(j['region'], 'Bodrum');
    });
  });

  group('Form doğrulama', () {
    test('ad', () {
      expect(CustomerValidators.name(''), isNotNull);
      expect(CustomerValidators.name('   '), isNotNull);
      expect(CustomerValidators.name('Ali'), isNull);
      expect(CustomerValidators.name('a' * 201), isNotNull);
    });

    test('telefon: zorunlu, 10-15 rakam, biçim serbest', () {
      expect(CustomerValidators.phone(''), isNotNull);
      expect(CustomerValidators.phone('0532 11'), contains('10 rakam'));
      expect(CustomerValidators.phone('0532 111 22 33'), isNull);
      expect(CustomerValidators.phone('+90 (532) 111-22-33'), isNull);
      expect(CustomerValidators.phone('1' * 16), isNotNull);
    });

    test('e-posta: boş serbest; çoklu/boşluklu adres geçersiz', () {
      expect(CustomerValidators.email(''), isNull);
      expect(CustomerValidators.email('a@b.com'), isNull);
      expect(CustomerValidators.email('a@b'), isNotNull);
      expect(CustomerValidators.email('a@b.com, c@d.com'), isNotNull);
      expect(CustomerValidators.email('Ad <a@b.com>'), isNotNull);
      expect(CustomerValidators.email('a b@c.com'), isNotNull);
    });

    test('azami uzunluk', () {
      expect(
        CustomerValidators.maxLen('a' * 501, 500, 'Adres'),
        contains('500'),
      );
      expect(CustomerValidators.maxLen('a', 500, 'Adres'), isNull);
    });
  });
}
