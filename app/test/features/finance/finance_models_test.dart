import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/finance/data/finance_models.dart';

void main() {
  const uuid = '03f27b91-d9f4-47be-9d03-014613707b36';

  group('Payment', () {
    test('sözleşme satırı (§5) çözülür; kuruş doğru', () {
      final p = Payment.fromJson({
        'id': 'p1',
        'project_id': uuid,
        'amount': 1250.5,
        'method': 'Havale',
        'note': 'Avans',
        'paid_at': '2026-11-20T09:00:00.000Z',
        'owner_id': 'u1',
        'customer_name': 'Ayşe Yılmaz',
        'project_code': 'PRJ-12',
      });
      expect(p.amount, Money.fromKurus(125050));
      expect(p.methodEnum, isNotNull);
      expect(p.paidAt, DateTime.utc(2026, 11, 20, 9));
      expect(p.projectLabel, 'PRJ-12 · Ayşe Yılmaz');
    });

    test('UUID asla etikette görünmez (kod/ad yoksa genel yedek)', () {
      final p = Payment.fromJson({
        'id': 'p1',
        'project_id': uuid,
        'amount': '10.00',
        'method': 'Nakit',
      });
      expect(p.projectLabel, 'Proje');
      expect(p.projectLabel.contains(uuid), isFalse);
      expect(FinanceLabels.project(code: null, customer: 'Ali'), 'Ali');
    });

    test('bilinmeyen yöntem olduğu gibi gösterilir (çek/senet gelecek)', () {
      final p = Payment.fromJson({'id': 'x', 'amount': 5, 'method': 'Çek'});
      expect(p.methodEnum, isNull);
      expect(p.methodLabel, 'Çek');
    });

    test('eksik/null alanlarda çökmez', () {
      final p = Payment.fromJson({});
      expect(p.amount, Money.zero);
      expect(p.paidAt, isNull);
    });
  });

  group('Expense ve kapsam', () {
    test(
      'ev → Ev, dukkan → Dükkan, genel → İşletme (eski panelle aynı adlar)',
      () {
        expect(ScopeView.fromApi('ev').label, 'Ev');
        expect(ScopeView.fromApi('ev').groupLabel, 'Ev Giderleri');
        expect(ScopeView.fromApi('dukkan').label, 'Dükkan');
        expect(ScopeView.fromApi('dukkan').groupLabel, 'Dükkan Giderleri');
        expect(ScopeView.fromApi('genel').label, 'İşletme');
        expect(ScopeView.fromApi('genel').groupLabel, 'İşletme Giderleri');
        expect(ScopeView.fromApi(null), ScopeView.general);
        expect(ScopeView.fromApi('???'), ScopeView.general);
        expect(ScopeView.personal.api, 'ev');
        expect(ScopeView.business.api, 'dukkan');
        expect(ScopeView.personal.isBusiness, isFalse);
      },
    );

    test('gider satırı; tarih expense_date yoksa created_at', () {
      final e = Expense.fromJson({
        'id': 'e1',
        'project_id': null,
        'category': 'Yakıt',
        'amount': 850,
        'created_at': '2026-11-18T06:00:00Z',
        'scope': 'ev',
      });
      expect(e.isPersonal, isTrue);
      expect(e.hasProject, isFalse);
      expect(e.date, DateTime.utc(2026, 11, 18, 6));
    });
  });

  group('ProjectRef', () {
    test('kalan = sözleşme + ilave − tahsilat; negatif olmaz', () {
      final p = ProjectRef.fromJson({
        'id': uuid,
        'code': 'PRJ-1',
        'customer_name': 'Veli',
        'total_amount': 26000,
        'paid_amount': 6000,
      });
      expect(p.remaining, Money.fromTl(20000));
      expect(
        p.copyWith(extras: Money.fromTl(500)).remaining,
        Money.fromTl(20500),
      );
      final over = p.copyWith(paid: Money.fromTl(30000));
      expect(over.remaining, Money.zero);
      expect(over.overpaid, isTrue);
      expect(p.displayLabel, 'PRJ-1 · Veli');
      expect(p.displayLabel.contains(uuid), isFalse);
    });
  });

  group('Girdi → gövde', () {
    test('ödeme: tutar noktalı metin, öğlen ISO, boş not null', () {
      final j = PaymentInput(
        amount: Money.fromKurus(1250050),
        method: 'Nakit',
        paidAt: DateTime.utc(2026, 11, 20, 23, 30), // İstanbul'da 21 Kas 02:30
        note: '  ',
      ).toJson();
      expect(j['amount'], '12500.50');
      expect(j['paid_at'], '2026-11-21T12:00:00+03:00');
      expect(j['note'], isNull);
      expect(j['method'], 'Nakit');
    });

    test('gider: proje yoksa project_id gönderilmez, scope sunucu değeri', () {
      final j = ExpenseInput(
        category: ' Yakıt ',
        amount: Money.fromTl(100),
        scope: ScopeView.personal,
        date: DateTime.utc(2026, 11, 20, 9),
      ).toCreateJson();
      expect(j.containsKey('project_id'), isFalse);
      expect(j['scope'], 'ev');
      expect(j['category'], 'Yakıt');
      expect(j['expense_date'], '2026-11-20T12:00:00+03:00');
      final withProject = ExpenseInput(
        category: 'Malzeme',
        amount: Money.fromTl(1),
        scope: ScopeView.general,
        date: DateTime.utc(2026, 11, 20),
        projectId: 'prj',
      ).toCreateJson();
      expect(withProject['project_id'], 'prj');
    });

    test('sabit gider PATCH active taşır', () {
      final j = RecurringInput(
        category: 'Kira',
        amount: Money.fromTl(15000),
        scope: ScopeView.business,
        active: false,
      ).toPatchJson();
      expect(j['active'], false);
      expect(j['scope'], 'dukkan');
    });
  });
}
