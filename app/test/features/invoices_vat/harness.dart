// Fatura/KDV testleri için ortak düzen: sahte API, yönlendiricili uygulama, rol yetkisi.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/auth/session.dart';
import 'package:xc_asistan/core/demo/demo_adapter.dart';
import 'package:xc_asistan/core/demo/demo_db.dart';
import 'package:xc_asistan/core/theme/app_theme.dart';
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_demo.dart';
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_repository.dart';
import 'package:xc_asistan/features/invoices_vat/invoices_vat_routes.dart';

import '../../helpers/fakes.dart';

ApiClient apiWith(ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api'));
  dio.httpClientAdapter = adapter;
  return ApiClient(dio);
}

/// Gerçek DEMO sahte API + bu özelliğin DEMO rotaları (kayıt koordinatörde; test elle ekler).
DemoHttpAdapter demoAdapter({DemoDb? db}) {
  final d = db ?? DemoDb(now: DateTime.utc(2026, 11, 20, 8, 0));
  final a = DemoHttpAdapter(d, latency: Duration.zero);
  a.routes.addAll(invoicesVatDemoRoutes(d));
  return a;
}

InvoicesVatRepository demoRepo({
  String role = 'admin',
  DemoHttpAdapter? adapter,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.test/api',
      headers: {'Authorization': 'Bearer demo-token-$role'},
    ),
  );
  dio.httpClientAdapter = adapter ?? demoAdapter();
  return HttpInvoicesVatRepository(ApiClient(dio));
}

/// Bir ekranı (ya da tüm özellik rotalarını) yönlendiriciyle açar.
Future<GoRouter> pumpFeature(
  WidgetTester tester, {
  String location = '/invoices-vat',
  UserRole role = UserRole.admin,
  List<Override> overrides = const [],
  FakeLinkLauncher? launcher,
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final base = await baseOverrides(launcher: launcher);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/today',
        builder: (_, _) => const Scaffold(body: Text('route:/today')),
      ),
      ...invoicesVatRoutes,
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...base,
        capabilitiesProvider.overrideWithValue(AppCapabilities.forRole(role)),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  return router;
}

Future<void> settle(WidgetTester tester, [int steps = 14]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}
