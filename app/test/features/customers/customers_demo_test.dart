import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/demo/demo_adapter.dart';
import 'package:xc_asistan/core/demo/demo_db.dart';
import 'package:xc_asistan/features/customers/data/customer_models.dart';
import 'package:xc_asistan/features/customers/data/customers_repository.dart';

CustomersRepository demoRepo({String role = 'admin'}) {
  final db = DemoDb(now: DateTime.utc(2026, 11, 20, 8));
  final dio = Dio(BaseOptions(baseUrl: 'https://demo.test/api'))
    ..httpClientAdapter = DemoHttpAdapter(db, latency: Duration.zero)
    ..options.headers['Authorization'] = 'Bearer demo-token-$role';
  return HttpCustomersRepository(ApiClient(dio));
}

void main() {
  test('DEMO: liste, X-Total-Count ve sayfalama', () async {
    final repo = demoRepo();
    final all = await repo.list();
    expect(all.items, isNotEmpty);
    final p1 = await repo.list(limit: 2);
    expect(p1.items.length, 2);
    expect(p1.total, all.items.length);
    final p2 = await repo.list(limit: 2, offset: 2);
    expect(p2.items.first.phoneKey, isNot(p1.items.first.phoneKey));
  });

  test('DEMO: telefon ile arama (boşluk/ülke kodu fark etmez)', () async {
    final repo = demoRepo();
    final byPhone = await repo.list(query: '+90 532 111 22 33');
    expect(byPhone.items.map((c) => c.name), contains('Ayşe Yılmaz'));
    final byName = await repo.list(query: 'ayşe');
    expect(byName.items.single.phoneKey, '05321112233');
  });

  test(
    'DEMO: ekle → 409 tekrar → düzenle → sil; türetilen müşteri düzenlenemez',
    () async {
      final repo = demoRepo();
      const input = CustomerInput(
        name: 'Yeni Müşteri',
        phone: '0555 000 11 22',
        address: 'Test Sok.',
      );
      final created = await repo.create(input);
      expect(created.phoneKey, '05550001122');
      expect((await repo.findByPhone('0555 000 11 22'))?.name, 'Yeni Müşteri');

      await expectLater(
        repo.create(input),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.conflict,
          ),
        ),
      );

      await repo.update(
        '05550001122',
        const CustomerInput(name: 'Yeni Adı', phone: '0555 000 11 22'),
      );
      expect((await repo.get('05550001122')).name, 'Yeni Adı');

      await expectLater(
        repo.update(
          '05321112233',
          const CustomerInput(name: 'x', phone: '05321112233'),
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('teklif'),
          ),
        ),
      );

      await repo.delete('05550001122');
      expect(await repo.findByPhone('05550001122'), isNull);
      // Türetilen müşteri silinmez (sessiz).
      await repo.delete('05321112233');
      expect(await repo.findByPhone('05321112233'), isNotNull);
    },
  );

  test('DEMO: doğrulama 400, kart geçmişi, rol 403', () async {
    final repo = demoRepo();
    await expectLater(
      repo.create(const CustomerInput(name: '', phone: '123')),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.validation,
        ),
      ),
    );
    final h = await repo.history('05321112233');
    expect(h.offers, isNotEmpty);
    for (final role in ['personel', 'saha']) {
      await expectLater(
        demoRepo(role: role).list(),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.forbidden,
          ),
        ),
      );
    }
  });
}
