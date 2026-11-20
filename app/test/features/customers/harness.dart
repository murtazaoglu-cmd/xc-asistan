// Bu özelliğin testleri için ortak düzen: yönlendiricili MaterialApp + rol yetkisi + sahte API.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/auth/session.dart';
import 'package:xc_asistan/core/theme/app_theme.dart';

import '../../helpers/fakes.dart';

/// Sahte HTTP bağdaştırıcılı ApiClient (repository testleri).
ApiClient apiWith(ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api'));
  dio.httpClientAdapter = adapter;
  return ApiClient(dio);
}

/// [child] kök sayfadır; bilinmeyen yollar "route: yol" yazısı gösterir.
Future<GoRouter> pumpScreen(
  WidgetTester tester,
  Widget child, {
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
    routes: [
      GoRoute(path: '/', builder: (_, _) => child),
      GoRoute(
        path: '/:a',
        builder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
        routes: [
          GoRoute(
            path: ':b',
            builder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
            routes: [
              GoRoute(
                path: ':c',
                builder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
              ),
            ],
          ),
        ],
      ),
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

/// Sonsuz iskelet animasyonu yüzünden pumpAndSettle yerine.
Future<void> settle(WidgetTester tester, [int steps = 10]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}
