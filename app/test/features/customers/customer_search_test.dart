import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/features/customers/data/customer_models.dart';
import 'package:xc_asistan/features/customers/data/customer_search.dart';

Customer c(String name, [String key = '']) =>
    Customer(phoneKey: key.isEmpty ? name : key, name: name);

void main() {
  group('normalizeQuery (telefon rakam eşleme)', () {
    test('metin aynen (kırpılır)', () {
      expect(CustomerSearch.normalizeQuery('  Ayşe '), 'Ayşe');
      expect(CustomerSearch.normalizeQuery(''), '');
    });

    test('telefon biçimleri rakamlara iner', () {
      expect(CustomerSearch.normalizeQuery('0532 111 22 33'), '05321112233');
      expect(CustomerSearch.normalizeQuery('(0532) 111-22'), '053211122');
      expect(CustomerSearch.normalizeQuery('532'), '532');
    });

    test('ülke kodu atılır: +90 / 0090 / 90…', () {
      expect(CustomerSearch.normalizeQuery('+90 532 111 22 33'), '05321112233');
      expect(
        CustomerSearch.normalizeQuery('0090 532 111 22 33'),
        '05321112233',
      );
      expect(CustomerSearch.normalizeQuery('905321112233'), '05321112233');
    });

    test('kısa rakam (<3) ve karışık metin dokunulmaz', () {
      expect(CustomerSearch.normalizeQuery('12'), '12');
      expect(CustomerSearch.normalizeQuery('Ev 12 numara'), 'Ev 12 numara');
    });

    test('en çok 100 karakter', () {
      expect(CustomerSearch.normalizeQuery('a' * 150).length, 100);
    });
  });

  group('Türkçe alfabetik sıra', () {
    test('Ç C den sonra D den önce; ı i den önce; ş s den sonra', () {
      final names = [
        'Zeynep',
        'Şule',
        'Çelik',
        'Ali',
        'Işık',
        'İbrahim',
        'Cem',
        'Davut',
        'Ömer',
        'Oya',
        'Ümit',
        'Ufuk',
        'Sema',
      ];
      final sorted = CustomerSearch.group(names.map(c))
          .expand((g) => g.customers)
          .map((e) => e.name)
          .toList();
      expect(sorted, [
        'Ali',
        'Cem',
        'Çelik',
        'Davut',
        'Işık',
        'İbrahim',
        'Oya',
        'Ömer',
        'Sema',
        'Şule',
        'Ufuk',
        'Ümit',
        'Zeynep',
      ]);
    });

    test('büyük/küçük harf ve İ/I farkı gözetilir', () {
      expect(CustomerSearch.compareTr('ışık', 'İpek') < 0, isTrue);
      expect(CustomerSearch.compareTr('ali', 'ALİ'), 0);
      expect(CustomerSearch.compareTr('Ali', 'Alic') < 0, isTrue);
    });
  });

  group('Gruplama', () {
    test('harf başlıkları; harf olmayanlar "#" ve en sonda', () {
      final g = CustomerSearch.group([
        c('1. Müşteri'),
        c('Ayşe'),
        c('ali'),
        c('İlker'),
        c('Işıl'),
        c(''),
      ]);
      expect(g.map((e) => e.letter).toList(), ['A', 'I', 'İ', '#']);
      expect(g[0].customers.map((e) => e.name), ['ali', 'Ayşe']);
      expect(g.last.customers.length, 2);
    });

    test('aynı ad: telefon anahtarına göre kararlı', () {
      final g = CustomerSearch.group([c('Ali', '2'), c('Ali', '1')]);
      expect(g.single.customers.map((e) => e.phoneKey), ['1', '2']);
    });

    test('boş liste', () {
      expect(CustomerSearch.group([]), isEmpty);
    });

    test('groupLetter', () {
      expect(CustomerSearch.groupLetter('çiğdem'), 'Ç');
      expect(CustomerSearch.groupLetter('ığdır'), 'I');
      expect(CustomerSearch.groupLetter('iğdir'), 'İ');
      expect(CustomerSearch.groupLetter('  '), '#');
    });
  });
}
