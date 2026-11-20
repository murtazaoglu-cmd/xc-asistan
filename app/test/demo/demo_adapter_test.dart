import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/api/api_providers.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/auth/auth_repository.dart';
import 'package:xc_asistan/core/config/app_config.dart';
import 'package:xc_asistan/core/demo/demo_adapter.dart';
import 'package:xc_asistan/core/demo/demo_db.dart';
import 'package:xc_asistan/features/home/data/home_repository.dart';

import '../helpers/fakes.dart';

Future<ProviderContainer> demo({String? token}) async {
  final store = await baseOverrides(
    config: const AppConfig(demo: true, retryBaseDelay: Duration.zero),
  );
  final c = ProviderContainer(
    overrides: [
      ...store,
      demoAdapterProvider.overrideWithValue(
        DemoHttpAdapter(
          DemoDb(now: DateTime.utc(2026, 11, 20, 8)),
          latency: Duration.zero,
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  c.read(tokenHolderProvider).token = token;
  return c;
}

void main() {
  test('giriş: e-postaya göre rol; hatalı şifre 401 → unauthorized', () async {
    final c = await demo();
    final repo = c.read(authRepositoryProvider);
    expect((await repo.login('saha@demo.com', 'x')).user!.role, UserRole.saha);
    expect((await repo.login('admin@demo.com', 'x')).token, 'demo-token-admin');
    await expectLater(
      repo.login('admin@demo.com', 'yanlis'),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.unauthorized,
        ),
      ),
    );
  });

  test('jetonsuz istek 401; me() rolün yetkilerini döner', () async {
    final c = await demo();
    await expectLater(
      c.read(authRepositoryProvider).me(),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.unauthorized,
        ),
      ),
    );
    c.read(tokenHolderProvider).token = 'demo-token-saha';
    final me = await c.read(authRepositoryProvider).me();
    expect(me.user.role, UserRole.saha);
    expect(me.capabilities.showFinance, isFalse);
  });

  test(
    '/mobile/home her rol için çözümlenir; saha finans/teklif bölümü almaz',
    () async {
      for (final role in ['admin', 'personel', 'saha']) {
        final c = await demo(token: 'demo-token-$role');
        final h = await c.read(homeRepositoryProvider).fetch();
        expect(h.userName, isNotEmpty, reason: role);
        expect(h.today, isNotEmpty, reason: role);
        if (role == 'saha') {
          expect(h.finance, isNull);
          expect(h.newOfferCount, isNull);
        }
      }
    },
  );

  test('rol dışı uç 403 → forbidden (saha /customers)', () async {
    final c = await demo(token: 'demo-token-saha');
    await expectLater(
      c.read(apiClientProvider).getList('/customers'),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.forbidden,
        ),
      ),
    );
  });

  test('bilinmeyen uç 404 → notFound; liste uçları parse edilir', () async {
    final c = await demo(token: 'demo-token-admin');
    final api = c.read(apiClientProvider);
    await expectLater(
      api.getMap('/yok-boyle-bir-uc'),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.notFound,
        ),
      ),
    );
    expect(await api.getList('/appointments'), isNotEmpty);
    expect(await api.getList('/materials'), isNotEmpty);
  });
}
