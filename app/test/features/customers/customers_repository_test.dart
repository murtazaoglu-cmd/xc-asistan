import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/customers/data/customer_models.dart';
import 'package:xc_asistan/features/customers/data/customers_repository.dart';

import '../../helpers/fakes.dart';
import 'harness.dart';

Map<String, dynamic> row(String key, String name) => {
  'phone_key': key,
  'name': name,
  'phone': key,
  'offer_count': 1,
  'project_count': 0,
  'total_contracted': 0,
  'total_paid': 0,
};

void main() {
  test(
    'list: q/limit/offset gider, X-Total-Count okunur, telefon normalleşir',
    () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(
          200,
          [row('05321112233', 'Ayşe')],
          {'x-total-count': '120'},
        ),
      );
      final repo = HttpCustomersRepository(apiWith(a));
      final page = await repo.list(
        query: '+90 532 111 22 33',
        limit: 50,
        offset: 100,
      );
      final q = a.requests.single.queryParameters;
      expect(a.requests.single.path, '/customers');
      expect(q, {'q': '05321112233', 'limit': 50, 'offset': 100});
      expect(page.total, 120);
      expect(page.items.single.name, 'Ayşe');
      expect(page.hasMore(100), isTrue);
    },
  );

  test('list: boş arama q göndermez', () async {
    final a = ScriptedAdapter((i, o) => ScriptedResponse(200, <dynamic>[]));
    await HttpCustomersRepository(apiWith(a)).list();
    expect(a.requests.single.queryParameters.containsKey('q'), isFalse);
  });

  test('findByPhone: aynı phone_key bulunur, benzer numara sayılmaz', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, [
        row('053211122330', 'Başkası'),
        row('05321112233', 'Ayşe'),
      ]),
    );
    final repo = HttpCustomersRepository(apiWith(a));
    expect((await repo.findByPhone('0532 111 22 33'))?.name, 'Ayşe');
    expect(await repo.findByPhone('12'), isNull); // <3 rakam: istek yok
    expect(a.requests.length, 1);
  });

  test('get: bulunamazsa notFound', () async {
    final a = ScriptedAdapter((i, o) => ScriptedResponse(200, <dynamic>[]));
    expect(
      HttpCustomersRepository(apiWith(a)).get('05320000000'),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.notFound,
        ),
      ),
    );
  });

  test('history: /customers/:phoneKey {offers, projects}', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, {
        'offers': [
          {'id': 'o1', 'status': 'Yeni'},
        ],
        'projects': [
          {'id': 'p1', 'total_amount': 100, 'paid_amount': 40},
        ],
      }),
    );
    final h = await HttpCustomersRepository(apiWith(a)).history('0532');
    expect(a.requests.single.path, '/customers/0532');
    expect(h.offers.single.id, 'o1');
    expect(h.projects.single.remaining, Money.fromTl(60));
  });

  test('create: POST gövdesi ve 201 satırı', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(201, row('05321112233', 'Ayşe')),
    );
    final c = await HttpCustomersRepository(apiWith(a)).create(
      const CustomerInput(name: 'Ayşe', phone: '0532 111 22 33', email: ''),
    );
    expect(a.requests.single.method, 'POST');
    expect(a.requests.single.data, {'name': 'Ayşe', 'phone': '0532 111 22 33'});
    expect(c.phoneKey, '05321112233');
  });

  test('create: 409 çakışma AppException(conflict)', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(409, {'error': 'Bu numara kayıtlı.'}),
    );
    expect(
      HttpCustomersRepository(apiWith(a))
          .create(const CustomerInput(name: 'A', phone: '05321112233')),
      throwsA(
        isA<AppException>()
            .having((e) => e.code, 'code', AppErrorCode.conflict)
            .having((e) => e.message, 'message', 'Bu numara kayıtlı.'),
      ),
    );
  });

  test(
    'update: PATCH, telefon yok; 404 → tekliften türeyen müşteri iletisi',
    () async {
      final a = ScriptedAdapter(
        (i, o) => i == 0
            ? ScriptedResponse(200, {'ok': true})
            : ScriptedResponse(404, {'error': 'Müşteri bulunamadı.'}),
      );
      final repo = HttpCustomersRepository(apiWith(a));
      const input = CustomerInput(name: 'Ayşe', phone: '0532 111 22 33');
      await repo.update('05321112233', input);
      expect(a.requests[0].method, 'PATCH');
      expect(a.requests[0].path, '/customers/05321112233');
      expect((a.requests[0].data as Map).containsKey('phone'), isFalse);
      await expectLater(
        repo.update('05321112233', input),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('teklif'),
          ),
        ),
      );
    },
  );

  test('delete: DELETE /customers/:phoneKey', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, {'message': 'ok'}),
    );
    await HttpCustomersRepository(apiWith(a)).delete('05321112233');
    expect(a.requests.single.method, 'DELETE');
    expect(a.requests.single.path, '/customers/05321112233');
  });

  test('403 (personel/saha) → forbidden', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(403, {'error': 'Bu işlem için yetkiniz yok.'}),
    );
    expect(
      HttpCustomersRepository(apiWith(a)).list(),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.forbidden,
        ),
      ),
    );
  });
}
