// Para ekranları için hafif test düzeneği: yalnız Para rotalarını DEMO sahte API ile kurar
// (tüm uygulama yönlendiricisine bağımlı değildir).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/api/api_providers.dart';
import 'package:xc_asistan/core/api/interceptors.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/config/app_config.dart';
import 'package:xc_asistan/core/demo/demo_adapter.dart';
import 'package:xc_asistan/core/demo/demo_db.dart';
import 'package:xc_asistan/core/theme/app_theme.dart';
import 'package:xc_asistan/features/finance/data/finance_access.dart';
import 'package:xc_asistan/features/finance/data/finance_providers.dart';
import 'package:xc_asistan/features/finance/finance_route_defs.dart';

import '../../helpers/fakes.dart';

class FinanceHandle {
  FinanceHandle(this.tester, this.container, this.router, this.launcher);
  final WidgetTester tester;
  final ProviderContainer container;
  final GoRouter router;
  final FakeLinkLauncher launcher;

  String get location => router.state.uri.toString();

  /// Sonsuz iskelet animasyonu yüzünden pumpAndSettle yerine kısa aralıklarla ilerler.
  Future<void> settle([int steps = 12]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
}

Future<FinanceHandle> pumpFinance(
  WidgetTester tester, {
  UserRole role = UserRole.admin,
  String initialLocation = '/finance',
  List<Override> extraOverrides = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final launcher = FakeLinkLauncher();
  final overrides = await baseOverrides(
    launcher: launcher,
    config: const AppConfig(demo: true, retryBaseDelay: Duration.zero),
  );
  final db = DemoDb(now: DateTime.utc(2026, 11, 20, 8, 0));
  final rootKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    routes: buildFinanceRoutes(parentKey: rootKey),
  );
  final container = ProviderContainer(
    overrides: [
      ...overrides,
      ...extraOverrides,
      demoAdapterProvider.overrideWithValue(
        DemoHttpAdapter(db, latency: Duration.zero),
      ),
      tokenHolderProvider.overrideWithValue(
        AuthTokenHolder()..token = 'demo-token-${role.api}',
      ),
      financeAccessProvider.overrideWithValue(
        FinanceAccess.of(AppCapabilities.forRole(role)),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
      ),
    ),
  );
  final h = FinanceHandle(tester, container, router, launcher);
  await h.settle(20);
  return h;
}
