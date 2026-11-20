import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_input.dart';
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_models.dart';
import 'package:xc_asistan/features/invoices_vat/data/vat_calc.dart';

Invoice inv(
  String dir,
  int matrah,
  int kdv, {
  int tevk = 0,
  String status = 'kesildi',
  bool deductible = true,
}) => Invoice.fromJson({
  'id': '$dir$matrah',
  'direction': dir,
  'matrah_kurus': matrah,
  'kdv_kurus': kdv,
  'tevkifat_kurus': tevk,
  'status': status,
  'kdv_indirilebilir': deductible,
});

void main() {
  group('KDV önizleme: kuruş doğruluğu', () {
    test('KDV hariç matrahtan: %20 ve toplam', () {
      final p = VatCalc.fromMatrah(Money.fromKurus(10000), 20);
      expect(p.kdv.kurus, 2000);
      expect(p.tutar.kurus, 12000);
      expect(p.odenecek.kurus, 12000);
      expect(p.tevkifat.kurus, 0);
    });

    test(
      'yarım kuruş yukarı yuvarlanır (matrah 12,34 TL, %20 → 2,468 → 2,47)',
      () {
        final p = VatCalc.fromMatrah(Money.fromKurus(1234), 20);
        expect(p.kdv.kurus, 247);
        expect(p.tutar.kurus, 1481);
      },
    );

    test('%10 ve %1 oranlar', () {
      expect(VatCalc.fromMatrah(Money.fromKurus(4500), 10).kdv.kurus, 450);
      expect(
        VatCalc.fromMatrah(Money.fromKurus(999), 1).kdv.kurus,
        10,
      ); // 9,99 → 0,0999 → 0,10
      expect(VatCalc.fromMatrah(Money.fromKurus(12345), 0).kdv.kurus, 0);
    });

    test('ondalık oran (%7,5) tamsayı baz puanla hesaplanır', () {
      expect(VatCalc.fromMatrah(Money.fromKurus(10000), 7.5).kdv.kurus, 750);
    });

    test('KDV dahil tutardan: kuruş kaybolmaz (matrah + KDV = tutar)', () {
      final p = VatCalc.fromGross(Money.fromKurus(12000), 20);
      expect(p.matrah.kurus, 10000);
      expect(p.kdv.kurus, 2000);
      final odd = VatCalc.fromGross(Money.fromKurus(9999), 20);
      expect(odd.matrah.kurus + odd.kdv.kurus, 9999);
      expect(odd.matrah.kurus, 8333); // 83,325 → 83,33? yarım yukarı
    });

    test('tevkifat 4/10: KDV × 4/10, ödenecek = toplam − tevkifat', () {
      final p = VatCalc.fromMatrah(
        Money.fromKurus(5333333),
        20,
        withholding: const Withholding(4, 10),
      );
      expect(p.kdv.kurus, 1066667);
      expect(p.tevkifat.kurus, 426667); // 4266668/10 → 426666,8 → 426667
      expect(p.tutar.kurus, 6400000);
      expect(p.odenecek.kurus, 6400000 - 426667);
    });

    test('geçersiz tevkifat uygulanmaz', () {
      final p = VatCalc.fromMatrah(
        Money.fromKurus(10000),
        20,
        withholding: const Withholding(12, 10),
      );
      expect(p.tevkifat.isZero, isTrue);
    });

    test('belge KDV toleransı: 5 kuruş dahil, 6 kuruş fark uyuşmaz', () {
      final c = Money.fromKurus(2000);
      expect(VatCalc.kdvMatches(Money.fromKurus(2005), c), isTrue);
      expect(VatCalc.kdvMatches(Money.fromKurus(1995), c), isTrue);
      expect(VatCalc.kdvMatches(Money.fromKurus(2006), c), isFalse);
    });
  });

  group('dönem önizlemesi', () {
    test('hesaplanan − indirilecek − devreden; ödenecek ≥ 0', () {
      final p = VatCalc.periodPreview([
        inv('giden', 100000, 20000),
        inv('giden', 50000, 10000, tevk: 4000),
        inv('gelen', 40000, 8000),
        inv('gelen', 10000, 2000, deductible: false),
      ], previousCarry: Money.fromKurus(1000));
      expect(p.hesaplanan.kurus, 20000 + 10000 - 4000);
      expect(p.indirilecek.kurus, 8000);
      expect(p.indirilemeyen.kurus, 2000);
      expect(p.net.kurus, 26000 - 8000 - 1000);
      expect(p.odenecek.kurus, 17000);
      expect(p.devreden.kurus, 0);
    });

    test('indirilecek fazla ise devreder', () {
      final p = VatCalc.periodPreview([
        inv('giden', 10000, 2000),
        inv('gelen', 50000, 10000),
      ]);
      expect(p.net.kurus, -8000);
      expect(p.odenecek.kurus, 0);
      expect(p.devreden.kurus, 8000);
    });

    test('taslak ve iptal sayılmaz', () {
      final p = VatCalc.periodPreview([
        inv('giden', 10000, 2000, status: 'taslak'),
        inv('giden', 10000, 2000, status: 'iptal'),
      ]);
      expect(p.hesaplanan.isZero, isTrue);
    });
  });

  group('taksit sihirbazı', () {
    test('eşit bölünür; vadeler aralıklı', () {
      final plan = InstallmentPlanner.generate(
        total: Money.fromKurus(300000),
        count: 3,
        firstDue: '2026-12-01',
        intervalDays: 30,
      );
      expect(plan.map((e) => e.amount.kurus), [100000, 100000, 100000]);
      expect(plan.map((e) => e.dueDate), [
        '2026-12-01',
        '2026-12-31',
        '2027-01-30',
      ]);
    });

    test('kuruş artığı SON taksite eklenir ve toplam tutar', () {
      final plan = InstallmentPlanner.generate(
        total: Money.fromKurus(100000), // 1000,00 TL / 3
        count: 3,
        firstDue: '2026-11-20',
      );
      expect(plan.map((e) => e.amount.kurus), [33333, 33333, 33334]);
      expect(Money.sum(plan.map((e) => e.amount)).kurus, 100000);
      expect(plan.first.index, 1);
      expect(plan.last.index, 3);
    });

    test('tek taksit tüm tutardır; 60 taksit toplamı korur', () {
      expect(
        InstallmentPlanner.generate(
          total: Money.fromKurus(12345),
          count: 1,
          firstDue: '2026-01-31',
        ).single.amount.kurus,
        12345,
      );
      final p = InstallmentPlanner.generate(
        total: Money.fromKurus(100001),
        count: 60,
        firstDue: '2026-01-01',
      );
      expect(p, hasLength(60));
      expect(Money.sum(p.map((e) => e.amount)).kurus, 100001);
      expect(p.last.amount.kurus, 1666 + 100001 - 1666 * 60);
    });

    test(
      'ay sonu aşan vadeler takvimde doğru kayar (yıl geçişi, artık yıl)',
      () {
        final p = InstallmentPlanner.generate(
          total: Money.fromKurus(900),
          count: 3,
          firstDue: '2027-12-31',
          intervalDays: 60,
        );
        expect(p.map((e) => e.dueDate), [
          '2027-12-31',
          '2028-02-29',
          '2028-04-29',
        ]);
      },
    );

    test('geçersiz giriş boş liste', () {
      expect(
        InstallmentPlanner.generate(
          total: Money.zero,
          count: 3,
          firstDue: '2026-01-01',
        ),
        isEmpty,
      );
      expect(
        InstallmentPlanner.generate(
          total: Money.fromKurus(100),
          count: 0,
          firstDue: '2026-01-01',
        ),
        isEmpty,
      );
      expect(
        InstallmentPlanner.generate(
          total: Money.fromKurus(100),
          count: 61,
          firstDue: '2026-01-01',
        ),
        isEmpty,
      );
      expect(
        InstallmentPlanner.generate(
          total: Money.fromKurus(100),
          count: 2,
          firstDue: 'bozuk',
        ),
        isEmpty,
      );
      expect(
        InstallmentPlanner.generate(
          total: Money.fromKurus(100),
          count: 2,
          firstDue: '2026-01-01',
          intervalDays: 0,
        ),
        isEmpty,
      );
    });
  });

  group('VKN / TCKN', () {
    test('uzunluk denetimi (10/11 hane)', () {
      expect(TaxIdCheck.check(''), TaxIdState.empty);
      expect(TaxIdCheck.check(null), TaxIdState.empty);
      expect(TaxIdCheck.check('12345'), TaxIdState.badLength);
      expect(TaxIdCheck.check('12345678a0'), TaxIdState.badLength);
      expect(TaxIdCheck.check('123456789012'), TaxIdState.badLength);
    });

    test('geçerli TCKN ve VKN sağlama toplamı', () {
      expect(
        TaxIdCheck.check('10000000146'),
        TaxIdState.ok,
      ); // bilinen geçerli TCKN
      expect(TaxIdCheck.check('10000000147'), TaxIdState.checksumFailed);
      expect(TaxIdCheck.check('0123456789'), TaxIdState.ok); // geçerli VKN
      expect(TaxIdCheck.check('0123456780'), TaxIdState.checksumFailed);
    });

    test('nihai tüketici sabit numarası geçerli sayılır', () {
      expect(TaxIdCheck.check('11111111111'), TaxIdState.ok);
    });

    test('sağlama toplamı yalnız UYARI; uzunluk hatası engelleyici', () {
      expect(InvoiceRules.taxId('10000000147'), isNull);
      expect(InvoiceRules.taxIdWarning('10000000147'), isNotNull);
      expect(InvoiceRules.taxId('123'), isNotNull);
      expect(InvoiceRules.taxIdWarning('10000000146'), isNull);
    });
  });

  group('form doğrulama', () {
    test('tutar', () {
      expect(InvoiceRules.amount(null), isNotNull);
      expect(InvoiceRules.amount(Money.zero), isNotNull);
      expect(InvoiceRules.amount(Money.fromKurus(-5)), isNotNull);
      expect(InvoiceRules.amount(Money.fromKurus(1)), isNull);
      expect(InvoiceRules.amount(Money.parseUserInput('12.500,50')), isNull);
    });

    test('karşı taraf, belge no, not', () {
      expect(InvoiceRules.counterparty('  '), isNotNull);
      expect(InvoiceRules.counterparty('Ahmet'), isNull);
      expect(InvoiceRules.counterparty('a' * 201), isNotNull);
      expect(InvoiceRules.invoiceNo('x' * 51), isNotNull);
      expect(InvoiceRules.note('x' * 501), isNotNull);
    });

    test('vade fatura tarihinden önce olamaz', () {
      expect(InvoiceRules.dueAfterIssue('2026-11-20', '2026-11-19'), isNotNull);
      expect(InvoiceRules.dueAfterIssue('2026-11-20', '2026-11-20'), isNull);
      expect(InvoiceRules.dueAfterIssue('2026-11-20', null), isNull);
    });

    test('tevkifat pay/payda', () {
      expect(InvoiceRules.withholding(null, null), isNull);
      expect(InvoiceRules.withholding(4, 10), isNull);
      expect(InvoiceRules.withholding(0, 10), isNotNull);
      expect(InvoiceRules.withholding(11, 10), isNotNull);
      expect(InvoiceRules.withholding(4, null), isNotNull);
    });

    test('sihirbaz: taksit sayısı, aralık, toplam', () {
      expect(InvoiceRules.installmentCount(0), isNotNull);
      expect(InvoiceRules.installmentCount(61), isNotNull);
      expect(InvoiceRules.installmentCount(12), isNull);
      expect(InvoiceRules.interval(0), isNotNull);
      expect(InvoiceRules.interval(30), isNull);
      expect(InvoiceRules.planTotal(Money.fromKurus(2), 3), isNotNull);
      expect(InvoiceRules.planTotal(Money.fromKurus(3), 3), isNull);
    });
  });

  group('gövde üretimi', () {
    test('matrah/tutar ayrımı, boş alanlar gönderilmez, tevkifat metni', () {
      final j = InvoiceInput(
        direction: InvoiceDirection.giden,
        issueDate: '2026-11-20',
        amount: Money.fromKurus(1000),
        basis: AmountBasis.exclusive,
        counterparty: ' Ali ',
        kdvOran: 20,
        withholding: Withholding(4, 10),
        invoiceType: InvoiceType.eArsiv,
        invoiceNo: '  ',
      ).toJson();
      expect(j['matrah_kurus'], 1000);
      expect(j.containsKey('tutar_kurus'), isFalse);
      expect(j['counterparty'], 'Ali');
      expect(j['tevkifat'], '4/10');
      expect(j['invoice_type'], 'e-arsiv');
      expect(j.containsKey('invoice_no'), isFalse);
      expect(j.containsKey('accept_mismatch'), isFalse);
    });
  });
}
