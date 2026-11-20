import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/money.dart';

void main() {
  group('Money', () {
    test('kuruşa çevirir ve ondalık hata yapmaz', () {
      expect(Money.fromTl(1250.5).kurus, 125050);
      expect(
        Money.fromTl(0.1).kurus + Money.fromTl(0.2).kurus,
        30,
      ); // 0.1+0.2 double hatası yok
      expect((Money.fromTl(0.1) + Money.fromTl(0.2)), Money.fromTl(0.3));
      expect(Money.fromTl(19.99).times(3).kurus, 5997);
    });

    test('JSON: sayı, int ve noktalı metin', () {
      expect(Money.fromJson(1250.5).kurus, 125050);
      expect(Money.fromJson(12).kurus, 1200);
      expect(Money.fromJson('1250.50').kurus, 125050);
      expect(Money.fromJson('-3.5').kurus, -350);
      expect(Money.tryFromJson(null), isNull);
      expect(Money.tryFromJson('abc'), isNull);
      expect(Money.fromJson('x'), Money.zero);
      expect(Money.fromJson('10.005').kurus, 1001); // en yakın kuruşa
    });

    test('toApiString noktalı, virgülsüz', () {
      expect(Money.fromKurus(125050).toApiString(), '1250.50');
      expect(Money.fromKurus(5).toApiString(), '0.05');
      expect(Money.fromKurus(-125000).toApiString(), '-1250.00');
      expect(Money.fromKurus(100).toJson(), '1.00');
    });

    test('gösterim ₺12.450,00', () {
      expect(Money.fromTl(12450).format(), '₺12.450,00');
      expect(Money.fromTl(0).format(), '₺0,00');
      expect(Money.fromTl(1234567.89).format(), '₺1.234.567,89');
      expect(Money.fromTl(-1250).format(), '−₺1.250,00');
      expect(Money.fromTl(12450).format(hideZeroKurus: true), '₺12.450');
      expect(Money.fromTl(12450.5).format(hideZeroKurus: true), '₺12.450,50');
      expect(Money.fromTl(999).format(symbol: false), '999,00');
    });

    test('KDV %20 tamsayı aritmetiği', () {
      final p = Money.fromTl(1000);
      expect(p.vat().kurus, 20000);
      expect(p.withVat(), Money.fromTl(1200));
      expect(Money.fromTl(1200).excludingVat(), Money.fromTl(1000));
      expect(Money.fromKurus(333).vat().kurus, 67); // 66.6 → 67
      expect(Money.fromKurus(-333).vat().kurus, -67);
    });

    test('toplam, karşılaştırma, negatif sıfırlama', () {
      expect(
        Money.sum([Money.fromTl(1), Money.fromTl(2.5)]),
        Money.fromTl(3.5),
      );
      expect(Money.fromTl(5) > Money.fromTl(4), isTrue);
      expect(Money.fromTl(-5).clampNonNegative(), Money.zero);
      expect(Money.fromTl(5).max(Money.fromTl(9)), Money.fromTl(9));
    });

    group('parseUserInput (Türkçe biçim)', () {
      test('binlik nokta / ondalık virgül', () {
        expect(Money.parseUserInput('12.500')?.kurus, 1250000); // 12,5 DEĞİL
        expect(Money.parseUserInput('12.500,50')?.kurus, 1250050);
        expect(Money.parseUserInput('1250,5')?.kurus, 125050);
        expect(Money.parseUserInput('1.250.000')?.kurus, 125000000);
        expect(Money.parseUserInput('12.5')?.kurus, 1250);
        expect(Money.parseUserInput('0.500')?.kurus, 50);
        expect(Money.parseUserInput('₺ 99')?.kurus, 9900);
        expect(Money.parseUserInput('250 TL')?.kurus, 25000);
        expect(Money.parseUserInput('-45,5')?.kurus, -4550);
      });
      test('geçersiz girişler null', () {
        expect(Money.parseUserInput(''), isNull);
        expect(Money.parseUserInput('abc'), isNull);
        expect(Money.parseUserInput('1,2,3'), isNull);
        expect(Money.parseUserInput('-'), isNull);
      });
    });
  });
}
