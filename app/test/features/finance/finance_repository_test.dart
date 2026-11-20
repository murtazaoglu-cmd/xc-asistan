import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/finance/data/finance_errors.dart';
import 'package:xc_asistan/features/finance/data/finance_models.dart';
import 'package:xc_asistan/features/finance/data/finance_repository.dart';

import '../../helpers/fakes.dart';

HttpFinanceRepository repo(ScriptedAdapter a) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api'))
    ..httpClientAdapter = a;
  return HttpFinanceRepository(ApiClient(dio));
}

void main() {
  test('ödemeler: GET /projects/payments/all', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, [
        {
          'id': 'p1',
          'project_id': 'prj',
          'amount': 4000,
          'method': 'Havale',
          'paid_at': '2026-11-12T09:00:00Z',
          'customer_name': 'Zeynep',
          'project_code': 'PRJ-501',
        },
      ]),
    );
    final l = await repo(a).listPayments();
    expect(a.requests.single.path, '/projects/payments/all');
    expect(l.single.projectLabel, 'PRJ-501 · Zeynep');
    expect(l.single.amount, Money.fromTl(4000));
  });

  test(
    'ödeme ekle: POST /projects/:id/payments, tutar noktalı metin',
    () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(201, {
          'id': 'new',
          'project_id': 'prj-1',
          'amount': 1250.5,
          'method': 'Nakit',
          'paid_at': '2026-11-20T09:00:00Z',
        }),
      );
      final p = await repo(a).createPayment(
        'prj-1',
        PaymentInput(
          amount: Money.fromKurus(125050),
          method: 'Nakit',
          paidAt: DateTime.utc(2026, 11, 20, 9),
        ),
      );
      final req = a.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/projects/prj-1/payments');
      final body = req.data as Map;
      expect(body['amount'], '1250.50');
      expect(body['method'], 'Nakit');
      expect(body['paid_at'], '2026-11-20T12:00:00+03:00');
      expect(body.containsKey('note'), isFalse); // boş not gönderilmez
      expect(p.id, 'new');
      expect(p.amount, Money.fromKurus(125050));
    },
  );

  test('ödeme güncelle/sil yolları', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, {
        'id': 'p9',
        'project_id': 'x',
        'amount': 10,
        'method': 'Havale',
      }),
    );
    final r = repo(a);
    await r.updatePayment(
      'p9',
      PaymentInput(
        amount: Money.fromTl(10),
        method: 'Havale',
        paidAt: DateTime.utc(2026, 11, 1),
        note: null,
      ),
    );
    await r.deletePayment('p9');
    expect(a.requests[0].method, 'PATCH');
    expect(a.requests[0].path, '/projects/payments/p9');
    expect((a.requests[0].data as Map)['note'], isNull); // PATCH notu temizler
    expect(a.requests[1].method, 'DELETE');
    expect(a.requests[1].path, '/projects/payments/p9');
  });

  test('gider ekle: POST /expenses, kapsam sunucu değeri', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(201, {
        'id': 'e1',
        'category': 'Ev Kirası',
        'amount': 12000,
        'scope': 'ev',
        'expense_date': '2026-11-20T09:00:00Z',
      }),
    );
    final e = await repo(a).createExpense(
      ExpenseInput(
        category: 'Ev Kirası',
        amount: Money.fromTl(12000),
        scope: ScopeView.personal,
        date: DateTime.utc(2026, 11, 20, 9),
      ),
    );
    final body = a.requests.single.data as Map;
    expect(a.requests.single.path, '/expenses');
    expect(body['scope'], 'ev');
    expect(body.containsKey('project_id'), isFalse);
    expect(e.isPersonal, isTrue);
  });

  test(
    'sabit gider uygula: 201; aynı ay 409 → AppException.conflict',
    () async {
      var n = 0;
      final a = ScriptedAdapter((i, o) {
        n++;
        return n == 1
            ? ScriptedResponse(201, {
                'id': 'e2',
                'category': 'Kira',
                'amount': 15000,
                'scope': 'dukkan',
              })
            : ScriptedResponse(409, {'error': 'Bu ay zaten eklenmiş.'});
      });
      final r = repo(a);
      final e = await r.applyRecurring('rec-1');
      expect(a.requests.first.path, '/recurring-expenses/rec-1/apply');
      expect(e.amount, Money.fromTl(15000));
      Object? caught;
      try {
        await r.applyRecurring('rec-1');
      } catch (err) {
        caught = err;
      }
      expect(caught, isA<AppException>());
      expect((caught as AppException).code, AppErrorCode.conflict);
      expect(FinanceErrors.isAlreadyApplied(caught), isTrue);
      expect(
        FinanceErrors.message(caught, FinanceOp.applyRecurring),
        FinanceErrors.recurringAlreadyApplied,
      );
    },
  );

  test('proje arama: ?q ve ?limit gönderilir', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, [
        {
          'id': 'prj-1',
          'code': 'PRJ-501',
          'customer_name': 'Zeynep',
          'total_amount': 8500,
          'paid_amount': 4000,
        },
      ]),
    );
    final l = await repo(a).searchProjects(query: ' zey ');
    expect(a.requests.single.path, '/projects');
    expect(a.requests.single.queryParameters['q'], 'zey');
    expect(a.requests.single.queryParameters['limit'], 30);
    expect(l.single.remaining, Money.fromTl(4500));
  });

  test('tüm projeler sayfa sayfa çekilir (X-Total-Count)', () async {
    final a = ScriptedAdapter((i, o) {
      final off = o.queryParameters['offset'] as int;
      final rows = off == 0
          ? List.generate(200, (k) => {'id': 'a$k', 'customer_name': 'A'})
          : List.generate(50, (k) => {'id': 'b$k', 'customer_name': 'B'});
      return ScriptedResponse(200, rows, {'x-total-count': '250'});
    });
    final l = await repo(a).allProjects();
    expect(l.length, 250);
    expect(a.requests.length, 2);
  });

  test('tek proje: ilave işler ve ödemeler toplanır', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, {
        'project': {
          'id': 'prj-1',
          'code': 'PRJ-1',
          'customer_name': 'Veli',
          'total_amount': 1000,
        },
        'payments': [
          {'amount': 100.1},
          {'amount': 200.2},
        ],
        'extras': [
          {'amount': 50},
          {'amount': -10},
        ],
      }),
    );
    final p = await repo(a).project('prj-1');
    expect(p.paid, Money.fromKurus(30030));
    expect(p.extras, Money.fromTl(40));
    expect(p.remaining, Money.fromKurus(100000 + 4000 - 30030));
  });

  test('müşteri telefonu: ad tam eşleşirse', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, [
        {'name': 'Ali Veli', 'phone': '0532 111 22 33'},
        {'name': 'Ali', 'phone': '0533 000 00 00'},
      ]),
    );
    expect(await repo(a).customerPhone('ali'), '0533 000 00 00');
    expect(await repo(a).customerPhone('Bulunmaz'), isNull);
    expect(await repo(a).customerPhone(' '), isNull);
  });

  group('Hata eşleme', () {
    AppException e(int s, [String? m]) =>
        AppException.fromResponse(s, m == null ? null : {'error': m});

    test('403 genel gider (personel) nazik mesaj', () {
      expect(
        FinanceErrors.message(e(403), FinanceOp.saveExpense, hasProject: false),
        FinanceErrors.generalExpenseForbidden,
      );
      expect(
        FinanceErrors.message(e(403), FinanceOp.savePayment),
        FinanceErrors.forbidden,
      );
    });

    test('400 sunucu mesajı korunur, yoksa genel doğrulama mesajı', () {
      expect(
        FinanceErrors.message(
          e(400, 'Tutar sıfırdan büyük olmalı.'),
          FinanceOp.savePayment,
        ),
        'Tutar sıfırdan büyük olmalı.',
      );
      expect(
        FinanceErrors.message(e(400), FinanceOp.savePayment),
        'Geçersiz veya eksik değer girildi.',
      );
    });

    test('5xx ayrıntısı gösterilmez; ağ hatası Türkçe', () {
      final m = FinanceErrors.message(
        AppException.fromResponse(500, {'error': 'SELECT * FROM ...'}),
        FinanceOp.load,
      );
      expect(m.contains('SELECT'), isFalse);
      expect(
        FinanceErrors.message(
          const AppException(AppErrorCode.network, AppException.networkMessage),
          FinanceOp.load,
        ),
        AppException.networkMessage,
      );
    });
  });
}
