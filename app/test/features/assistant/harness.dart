// Asistan testleri için ortak düzen: asistan DEMO uçlarını sahte HTTP olarak sunar; repository
// gerçek HTTP koduyla çalışır.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/auth/session.dart';
import 'package:xc_asistan/core/demo/demo_db.dart';
import 'package:xc_asistan/core/demo/demo_router.dart';
import 'package:xc_asistan/core/theme/app_theme.dart';
import 'package:xc_asistan/features/assistant/data/assistant_demo.dart';
import 'package:xc_asistan/features/assistant/data/assistant_repository.dart';

import '../../helpers/fakes.dart';

/// Yalnız asistan demo uçlarını sunan bağdaştırıcı. [role] jeton olarak gönderilir.
class AssistantDemoAdapter implements HttpClientAdapter {
  AssistantDemoAdapter({DemoDb? db})
    : routes = assistantDemoRoutes(
        db ?? DemoDb(now: DateTime.utc(2026, 11, 20, 8)),
      );
  final List<DemoRoute> routes;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    var path = options.uri.path;
    final base = Uri.parse(options.baseUrl).path;
    if (base.isNotEmpty && base != '/' && path.startsWith(base))
      path = path.substring(base.length);
    final auth = options.headers['Authorization']?.toString();
    final token = (auth != null && auth.startsWith('Bearer '))
        ? auth.substring(7)
        : null;
    final method = options.method.toUpperCase();
    DemoResponse res = DemoResponse.error(404, 'Kayıt bulunamadı.');
    for (final r in routes) {
      final p = r.match(method, path);
      if (p == null) continue;
      res = r.handler(
        DemoRequest(
          method: method,
          path: path,
          query: options.uri.queryParameters,
          body: options.data,
          params: p,
          token: token,
        ),
      );
      break;
    }
    return ResponseBody.fromString(
      jsonEncode(res.body),
      res.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final e in res.headers.entries) e.key.toLowerCase(): [e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient apiWith(HttpClientAdapter adapter, {UserRole role = UserRole.admin}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.test/api',
      headers: {'Authorization': 'Bearer demo-token-${role.api}'},
    ),
  );
  dio.httpClientAdapter = adapter;
  return ApiClient(dio);
}

HttpAssistantRepository demoRepo({
  UserRole role = UserRole.admin,
  AssistantDemoAdapter? adapter,
}) => HttpAssistantRepository(
  apiWith(adapter ?? AssistantDemoAdapter(), role: role),
);

/// Repository + rol yetkisi override'ları.
Future<List<Override>> assistantOverrides({
  UserRole role = UserRole.admin,
  AssistantRepository? repo,
  AssistantDemoAdapter? adapter,
  FakeLinkLauncher? launcher,
  FakeNotificationsGateway? gateway,
  Map<String, Object> prefs = const {},
}) async {
  final base = await baseOverrides(
    launcher: launcher,
    gateway: gateway,
    prefsValues: prefs,
  );
  return [
    ...base,
    capabilitiesProvider.overrideWithValue(AppCapabilities.forRole(role)),
    assistantRepositoryProvider.overrideWithValue(
      repo ?? demoRepo(role: role, adapter: adapter),
    ),
  ];
}

ProviderContainer containerFor(List<Override> overrides) {
  final c = ProviderContainer(overrides: overrides);
  addTearDown(c.dispose);
  return c;
}

Future<GoRouter> pumpScreen(
  WidgetTester tester,
  Widget child, {
  UserRole role = UserRole.admin,
  List<Override> overrides = const [],
  AssistantDemoAdapter? adapter,
  FakeLinkLauncher? launcher,
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final base = await assistantOverrides(
    role: role,
    adapter: adapter,
    launcher: launcher,
  );
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
      overrides: [...base, ...overrides],
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

Future<void> settle(WidgetTester tester, [int steps = 12]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}
