import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/api/interceptors.dart';

import '../helpers/fakes.dart';

ApiClient client(
  ScriptedAdapter adapter, {
  AuthTokenHolder? holder,
  void Function(String)? onUnauthorized,
  List<Duration>? delays,
  int maxRetries = 2,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api'));
  dio.httpClientAdapter = adapter;
  dio.interceptors.addAll([
    AuthInterceptor(
      holder: holder ?? AuthTokenHolder(),
      onUnauthorized: onUnauthorized ?? (_) {},
    ),
    RetryInterceptor(
      dio: dio,
      maxRetries: maxRetries,
      baseDelay: const Duration(milliseconds: 100),
      delay: (d) async => delays?.add(d),
    ),
  ]);
  return ApiClient(dio);
}

void main() {
  group('AppException eşlemesi (sözleşme §0)', () {
    test('durum kodu → kod + Türkçe mesaj', () {
      expect(
        AppException.fromResponse(400, {
          'error': 'Geçersiz veya eksik değer girildi.',
        }).code,
        AppErrorCode.validation,
      );
      expect(
        AppException.fromResponse(401, {
          'error': 'E-posta veya şifre hatalı.',
        }).message,
        'E-posta veya şifre hatalı.',
      );
      expect(
        AppException.fromResponse(401, null).message,
        contains('Oturum süresi doldu'),
      );
      expect(AppException.fromResponse(403, null).code, AppErrorCode.forbidden);
      expect(AppException.fromResponse(404, null).code, AppErrorCode.notFound);
      expect(
        AppException.fromResponse(409, {'error': 'Bu ay zaten eklenmiş.'}).code,
        AppErrorCode.conflict,
      );
      expect(
        AppException.fromResponse(413, {'error': 'raw'}).message,
        contains('çok büyük'),
      );
      expect(AppException.fromResponse(429, null).code, AppErrorCode.rateLimit);
      expect(AppException.fromResponse(418, null).code, AppErrorCode.unknown);
    });

    test('5xx ham hata metni kullanıcıya gösterilmez (SQL maskeleme)', () {
      final e = AppException.fromResponse(500, {
        'error': 'column pay.owner_id does not exist',
      });
      expect(e.code, AppErrorCode.server);
      expect(e.message, AppException.serverMessage);
      expect(e.message, isNot(contains('column')));
      expect(e.body, isNotNull); // ayrıntı günlük için saklanır
    });

    test('Dio hata türleri', () {
      final o = RequestOptions(path: '/x');
      DioException d(DioExceptionType t) =>
          DioException(requestOptions: o, type: t);
      expect(
        AppException.fromDio(d(DioExceptionType.connectionTimeout)).code,
        AppErrorCode.network,
      );
      expect(
        AppException.fromDio(d(DioExceptionType.receiveTimeout)).message,
        AppException.timeoutMessage,
      );
      expect(
        AppException.fromDio(d(DioExceptionType.connectionError)).message,
        AppException.networkMessage,
      );
      expect(
        AppException.from(d(DioExceptionType.connectionError)).isNetwork,
        isTrue,
      );
      expect(AppException.from(StateError('x')).code, AppErrorCode.unknown);
    });
  });

  group('ApiClient', () {
    test('Bearer + X-Client: mobile eklenir; JSON gövde', () async {
      final a = ScriptedAdapter((i, o) => ScriptedResponse(200, {'ok': true}));
      final holder = AuthTokenHolder()..token = 'abc';
      final c = client(a, holder: holder);
      expect(await c.getMap('/health'), {'ok': true});
      final h = a.requests.single.headers;
      expect(h['Authorization'], 'Bearer abc');
      expect(h['X-Client'], 'mobile');
    });

    test('noAuth isteklerinde Authorization yok', () async {
      final a = ScriptedAdapter((i, o) => ScriptedResponse(200, {}));
      final c = client(a, holder: AuthTokenHolder()..token = 'abc');
      await c.send('POST', '/auth/login', extra: {ApiExtra.noAuth: true});
      expect(a.requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('hata gövdesi {error} → AppException', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(409, {'error': 'Bu ay zaten eklenmiş.'}),
      );
      final c = client(a);
      await expectLater(
        c.post('/recurring-expenses/1/apply'),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', AppErrorCode.conflict)
              .having((e) => e.message, 'message', 'Bu ay zaten eklenmiş.'),
        ),
      );
    });

    test('sayfalı liste: X-Total-Count başlığı', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(
          200,
          [
            {'id': 1},
            {'id': 2},
          ],
          {'x-total-count': '57'},
        ),
      );
      final p = await client(a)
          .getPaged('/offers', query: {'limit': 2, 'q': ''});
      expect(p.items.length, 2);
      expect(p.total, 57);
      expect(p.hasMore(0), isTrue);
      // boş sorgu parametresi gönderilmez
      expect(a.requests.single.uri.queryParameters, {'limit': '2'});
    });

    test('207/502 özel işleme: acceptStatuses ile gövde okunur', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(i == 0 ? 207 : 502, {
          'sent': i == 0,
          'status': i == 0 ? 'kismen' : 'basarisiz',
          'error': 'x',
        }),
      );
      final c = client(a);
      final r1 = await c.send(
        'POST',
        '/quotes/1/send',
        acceptStatuses: {207, 502},
      );
      expect(r1.statusCode, 207);
      expect(r1.map['status'], 'kismen');
      final r2 = await c.send(
        'POST',
        '/quotes/1/send',
        acceptStatuses: {207, 502},
      );
      expect(r2.statusCode, 502);
      expect(r2.map['sent'], false);
      // kabul edilmeyen 502 hata olur (ve POST olduğu için yeniden denenmez)
      final b = ScriptedAdapter(
        (i, o) => ScriptedResponse(502, {'sent': false}),
      );
      await expectLater(
        client(b).post('/quotes/1/send'),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.server,
          ),
        ),
      );
      expect(b.requests.length, 1);
    });
  });

  group('yeniden deneme (yalnız güvenli GET, üstel bekleme)', () {
    test('GET ağ hatasında 2 kez dener, üstel bekler, sonra başarır', () async {
      final delays = <Duration>[];
      final a = ScriptedAdapter(
        (i, o) => i < 2
            ? ScriptedResponse.error(DioExceptionType.connectionError, o)
            : ScriptedResponse(200, {'ok': 1}),
      );
      final c = client(a, delays: delays);
      expect(await c.getMap('/x'), {'ok': 1});
      expect(a.requests.length, 3);
      expect(delays.length, 2);
      expect(delays[0].inMilliseconds, inInclusiveRange(100, 199));
      expect(delays[1].inMilliseconds, inInclusiveRange(200, 299));
    });

    test('GET 503 yeniden denenir, deneme sınırı aşılınca hata', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(503, {'error': 'x'}),
      );
      await expectLater(
        client(a).get('/x'),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.server,
          ),
        ),
      );
      expect(a.requests.length, 3); // 1 + 2 deneme
    });

    test(
      'POST/PATCH/DELETE asla yeniden denenmez (çift kayıt riski)',
      () async {
        for (final m in ['POST', 'PATCH', 'DELETE']) {
          final a = ScriptedAdapter(
            (i, o) =>
                ScriptedResponse.error(DioExceptionType.connectionTimeout, o),
          );
          await expectLater(
            client(a).send(m, '/x'),
            throwsA(
              isA<AppException>().having((e) => e.isNetwork, 'network', isTrue),
            ),
          );
          expect(a.requests.length, 1, reason: m);
        }
      },
    );

    test('4xx yeniden denenmez; noRetry bayrağına uyulur', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(404, {'error': 'yok'}),
      );
      await expectLater(client(a).get('/x'), throwsA(isA<AppException>()));
      expect(a.requests.length, 1);
      final b = ScriptedAdapter(
        (i, o) => ScriptedResponse.error(DioExceptionType.connectionError, o),
      );
      await expectLater(
        client(b).send('GET', '/x', extra: {ApiExtra.noRetry: true}),
        throwsA(isA<AppException>()),
      );
      expect(b.requests.length, 1);
    });
  });

  group('401 işleme', () {
    test('reddedilen jeton geri çağrıya iletilir', () async {
      final rejected = <String>[];
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(401, {'error': 'Oturum geçersiz.'}),
      );
      final c = client(
        a,
        holder: AuthTokenHolder()..token = 'tok1',
        onUnauthorized: rejected.add,
      );
      await expectLater(
        c.get('/auth/me'),
        throwsA(
          isA<AppException>().having((e) => e.isUnauthorized, 'unauth', true),
        ),
      );
      expect(rejected, ['tok1']);
    });

    test(
      'skipUnauthorized (giriş) ve jetonsuz istek oturumu düşürmez',
      () async {
        final rejected = <String>[];
        final a = ScriptedAdapter(
          (i, o) =>
              ScriptedResponse(401, {'error': 'E-posta veya şifre hatalı.'}),
        );
        final c = client(
          a,
          holder: AuthTokenHolder()..token = 'tok1',
          onUnauthorized: rejected.add,
        );
        await expectLater(
          c.send(
            'POST',
            '/auth/login',
            extra: {ApiExtra.noAuth: true, ApiExtra.skipUnauthorized: true},
          ),
          throwsA(isA<AppException>()),
        );
        final c2 = client(a, onUnauthorized: rejected.add);
        await expectLater(c2.get('/x'), throwsA(isA<AppException>()));
        expect(rejected, isEmpty);
      },
    );
  });
}
