import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/features/appointments/data/appointment_models.dart';
import 'package:xc_asistan/features/appointments/data/appointments_repository.dart';

import '../../helpers/fakes.dart';

HttpAppointmentsRepository repo(ScriptedAdapter a) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api'))
    ..httpClientAdapter = a;
  return HttpAppointmentsRepository(ApiClient(dio));
}

Map<String, dynamic> row(String id, String at, {String status = 'beklemede'}) =>
    {
      'id': id,
      'type': 'Keşif',
      'scheduled_at': at,
      'status': status,
      'customer_name': 'Ayşe',
    };

void main() {
  test(
    'list: from/to UTC ISO, assigned_user_id=me, saate göre sıralı',
    () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(200, [
          row('b', '2026-11-20T12:00:00Z'),
          row('a', '2026-11-20T08:00:00Z'),
          {
            'id': 'zz',
            'type': 'Keşif',
            'status': 'beklemede',
          }, // zamansız → sona
        ]),
      );
      final r = repo(a);
      final range = Ist.dayRange(DateTime.utc(2026, 11, 20, 9));
      final list = await r.list(range: range, assignedUserId: 'me');
      expect(list.map((e) => e.id), ['a', 'b', 'zz']);
      final q = a.requests.single.uri.queryParameters;
      expect(a.requests.single.method, 'GET');
      expect(a.requests.single.uri.path, '/api/appointments');
      expect(q['from'], '2026-11-19T21:00:00.000Z');
      expect(q['to'], '2026-11-20T21:00:00.000Z');
      expect(q['assigned_user_id'], 'me');
      expect(q.containsKey('status'), isFalse);
    },
  );

  test('list: süzgeçsiz çağrıda sorgu parametresi yok', () async {
    final a = ScriptedAdapter((i, o) => ScriptedResponse(200, []));
    await repo(a).list();
    expect(a.requests.single.uri.query, isEmpty);
  });

  test('get', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, row('x', '2026-11-20T08:00:00Z')),
    );
    final e = await repo(a).get('x');
    expect(e.id, 'x');
    expect(a.requests.single.uri.path, '/api/appointments/x');
  });

  test('create: POST gövdesi İstanbul ofsetli, 201 yanıtı çözülür', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(201, row('n', '2026-11-21T06:00:00Z')),
    );
    final created = await repo(a).create(
      AppointmentDraft(
        type: 'Keşif',
        scheduledAt: Ist.fromWall(2026, 11, 21, 9),
        customerName: 'Ayşe',
        offerId: 'o1',
      ),
    );
    expect(created.id, 'n');
    final req = a.requests.single;
    expect(req.method, 'POST');
    expect(req.data, {
      'type': 'Keşif',
      'scheduled_at': '2026-11-21T09:00:00+03:00',
      'offer_id': 'o1',
      'customer_name': 'Ayşe',
    });
  });

  test('setStatus / reschedule / patch: PATCH gövdesi', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, row('x', '2026-11-20T08:00:00Z')),
    );
    final r = repo(a);
    await r.setStatus('x', 'tamamlandı');
    await r.reschedule('x', Ist.fromWall(2026, 11, 22, 10, 30));
    await r.patch('x', {'notes': null});
    expect(a.requests.map((e) => e.method), everyElement('PATCH'));
    expect(a.requests[0].data, {'status': 'tamamlandı'});
    expect(a.requests[1].data, {'scheduled_at': '2026-11-22T10:30:00+03:00'});
    expect(a.requests[2].data, {'notes': null});
  });

  test('delete', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, {'message': 'Randevu silindi.'}),
    );
    await repo(a).delete('x');
    expect(a.requests.single.method, 'DELETE');
    expect(a.requests.single.uri.path, '/api/appointments/x');
  });

  group('hata eşleme (AppException)', () {
    Future<AppException> fail(int status, [Object? body]) async {
      final a = ScriptedAdapter((i, o) => ScriptedResponse(status, body));
      try {
        await repo(a).setStatus('x', 'iptal');
      } on AppException catch (e) {
        return e;
      }
      throw StateError('hata bekleniyordu');
    }

    test('400 → validation, sunucunun Türkçe mesajı', () async {
      final e = await fail(400, {
        'error': 'Geçersiz veya eksik değer girildi.',
      });
      expect(e.code, AppErrorCode.validation);
      expect(e.message, 'Geçersiz veya eksik değer girildi.');
    });
    test('403 → forbidden (saha yasak alan)', () async {
      final e = await fail(403, {'error': 'Bu işlem için yetkiniz yok.'});
      expect(e.code, AppErrorCode.forbidden);
    });
    test('404 → notFound', () async {
      expect((await fail(404)).code, AppErrorCode.notFound);
    });
    test('409 → conflict', () async {
      expect(
        (await fail(409, {'error': 'Çakışma'})).code,
        AppErrorCode.conflict,
      );
    });
    test('500 → server, ayrıntı maskelenir', () async {
      final e = await fail(500, {'error': 'SQL hatası: secret'});
      expect(e.code, AppErrorCode.server);
      expect(e.message, isNot(contains('SQL')));
    });
    test('bağlantı hatası → network', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse.error(DioExceptionType.connectionError, o),
      );
      await expectLater(
        repo(a).list(),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.network,
          ),
        ),
      );
    });
  });

  group('search (seçici)', () {
    test('teklif/proje/müşteri uçları, q ve limit', () async {
      final a = ScriptedAdapter((i, o) {
        if (o.uri.path.endsWith('/offers')) {
          return ScriptedResponse(200, [
            {'id': 'o1', 'name': 'Ayşe', 'code': 'OFR-1'},
          ]);
        }
        if (o.uri.path.endsWith('/projects')) {
          return ScriptedResponse(200, [
            {'id': 'p1', 'customer_name': 'Ali', 'code': 'PRJ-1'},
          ]);
        }
        return ScriptedResponse(200, [
          {'phone_key': '0532', 'name': 'Veli', 'phone': '0532'},
        ]);
      });
      final r = repo(a);
      final o = await r.search(LinkKind.offer, ' ayş ');
      final p = await r.search(LinkKind.project, '');
      final c = await r.search(LinkKind.customer, 'v', limit: 5);
      expect(o.single.kind, LinkKind.offer);
      expect(p.single.title, 'Ali');
      expect(c.single.id, '0532');
      expect(a.requests[0].uri.queryParameters, {'q': 'ayş', 'limit': '20'});
      expect(
        a.requests[1].uri.queryParameters.containsKey('q'),
        isFalse,
      ); // boş q gönderilmez
      expect(a.requests[2].uri.queryParameters, {'q': 'v', 'limit': '5'});
    });

    test('q 100 karaktere kısaltılır (sözleşme §6)', () async {
      final a = ScriptedAdapter((i, o) => ScriptedResponse(200, []));
      await repo(a).search(LinkKind.offer, 'x' * 150);
      expect(a.requests.single.uri.queryParameters['q'], hasLength(100));
    });
  });
}
