// home + appointments testleri için ortak donanım: yalnız bu iki özelliğin DEMO rotalarını sunan
// sahte HTTP bağdaştırıcı, sabit saat (20 Kas 2026 11:00 İstanbul) ve rol bazlı oturum.
// Gerçek uygulama kabuğunu (diğer ajanların ekranlarını) İÇE AKTARMAZ: bağımsız çalışır.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/api/api_providers.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/auth/session.dart';
import 'package:xc_asistan/core/demo/demo_db.dart';
import 'package:xc_asistan/core/demo/demo_router.dart';
import 'package:xc_asistan/core/router/routes.dart';
import 'package:xc_asistan/core/theme/app_theme.dart';
import 'package:xc_asistan/features/appointments/appointments_routes.dart';
import 'package:xc_asistan/features/appointments/data/appointments_demo.dart';
import 'package:xc_asistan/features/home/application/home_controller.dart';
import 'package:xc_asistan/features/home/data/home_demo.dart';
import 'package:xc_asistan/features/home/presentation/home_screen.dart';
import 'package:xc_asistan/core/util/dates.dart';

import '../../helpers/fakes.dart';

/// 20 Kas 2026 08:00 UTC = 11:00 İstanbul.
final DateTime kNow = DateTime.utc(2026, 11, 20, 8);

/// Verilen DEMO rotalarıyla çalışan Dio bağdaştırıcısı (jeton `demo-token-<rol>`).
class RoutesAdapter implements HttpClientAdapter {
  RoutesAdapter(this.routes, {this.role = 'admin'});
  final List<DemoRoute> routes;
  final String role;
  final List<RequestOptions> requests = [];

  /// Doluysa her istek bu hatayla düşer (çevrimdışı testi).
  DioException? failWith;

  /// Her isteğe uygulanacak yapay gecikme (iskelet testi).
  Completer<void>? gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
    var path = options.uri.path;
    final base = Uri.parse(options.baseUrl).path;
    if (base.length > 1 && path.startsWith(base)) {
      path = path.substring(base.length);
    }
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
          token: 'demo-token-$role',
        ),
      );
      break;
    }
    return ResponseBody.fromString(
      jsonEncode(res.body),
      res.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class TestSession extends SessionNotifier {
  TestSession(this.initial);
  final SessionState initial;
  @override
  SessionState build() => initial;
}

SessionAuthenticated sessionFor(UserRole role) {
  final names = {
    UserRole.admin: 'Yönetici',
    UserRole.muhasebe: 'Muhasebe',
    UserRole.ortak: 'Ortak Firma',
    UserRole.personel: 'Personel',
    UserRole.saha: 'Saha Ekibi',
  };
  final team = role == UserRole.saha
      ? const [UserRef(id: 'u-admin', name: 'Yönetici', role: 'admin')]
      : const [
          UserRef(id: 'u-personel', name: 'Personel', role: 'personel'),
          UserRef(id: 'u-saha', name: 'Saha Ekibi', role: 'saha'),
        ];
  final user = AuthUser(
    id: 'u-${role.api}',
    name: names[role]!,
    email: '${role.api}@demo.com',
    role: role,
  );
  return SessionAuthenticated(
    MeResponse(
      user: user,
      capabilities: AppCapabilities.forRole(role),
      team: team,
    ),
  );
}

class FeatureHandle {
  FeatureHandle(
    this.tester,
    this.container,
    this.router,
    this.adapter,
    this.db,
  );
  final WidgetTester tester;
  final ProviderContainer container;
  final GoRouter router;
  final RoutesAdapter adapter;
  final DemoDb db;

  String get location => router.state.uri.toString();

  /// Sonsuz iskelet animasyonu yüzünden pumpAndSettle yerine kısa adımlar.
  Future<void> settle([int steps = 12]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> go(String path) async {
    router.go(path);
    await settle();
  }

  Future<void> push(String path) async {
    router.push(path);
    await settle();
  }
}

/// Bugün ekranını ve randevu rotalarını verilen rolle açar.
Future<FeatureHandle> pumpFeature(
  WidgetTester tester, {
  UserRole role = UserRole.admin,
  String initialLocation = '/today',
  List<Override> overrides = const [],
  RoutesAdapter? adapter,
  DemoDb? db,
  bool autoRefresh = false,
  Size surface = const Size(1080, 4200),
  DioException? failWith,
  Completer<void>? gate,
}) async {
  Ist.clock = () => kNow;
  addTearDown(() => Ist.clock = DateTime.now);
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final demoDb = db ?? DemoDb(now: kNow);
  final ad =
      adapter ??
      RoutesAdapter([
        ...homeDemoRoutes(demoDb),
        ...appointmentsDemoRoutes(demoDb),
        // Seçici uçları (jobs/customers ajanlarının işi): burada küçük sahte veri.
        DemoRoute('GET', '/offers', (req) {
          final q = (req.query['q'] ?? '').toLowerCase();
          return DemoResponse.json(
            demoDb.offers
                .where(
                  (o) =>
                      q.isEmpty ||
                      (o['name'] as String).toLowerCase().contains(q),
                )
                .toList(),
          );
        }),
        DemoRoute('GET', '/projects', (req) {
          final q = (req.query['q'] ?? '').toLowerCase();
          return DemoResponse.json(
            demoDb.projects
                .where(
                  (p) =>
                      q.isEmpty ||
                      (p['customer_name'] as String).toLowerCase().contains(q),
                )
                .toList(),
          );
        }),
        DemoRoute('GET', '/customers', (req) => DemoResponse.json([])),
      ], role: role.api);
  ad.failWith = failWith ?? ad.failWith;
  ad.gate = gate ?? ad.gate;
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api'))
    ..httpClientAdapter = ad;

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: Routes.today, builder: (_, _) => const HomeScreen()),
      ...appointmentsRoutes,
      // Diğer ajanların rotaları yerine yalnız varış denetimi için kuru rotalar.
      GoRoute(
        path: '/jobs',
        builder: (_, _) => const Scaffold(body: Text('JOBS')),
        routes: [
          GoRoute(
            path: 'offers/:id',
            builder: (_, s) =>
                Scaffold(body: Text('OFFER ${s.pathParameters['id']}')),
          ),
          GoRoute(
            path: 'projects/:id',
            builder: (_, s) =>
                Scaffold(body: Text('PROJECT ${s.pathParameters['id']}')),
          ),
        ],
      ),
      GoRoute(
        path: Routes.finance,
        builder: (_, _) => const Scaffold(body: Text('FINANCE')),
      ),
      GoRoute(
        path: Routes.stock,
        builder: (_, _) => const Scaffold(body: Text('STOCK')),
      ),
    ],
  );

  final base = await baseOverrides();
  final container = ProviderContainer(
    overrides: [
      ...base,
      dioProvider.overrideWithValue(dio),
      sessionProvider.overrideWith(() => TestSession(sessionFor(role))),
      if (!autoRefresh) homeAutoRefreshProvider.overrideWithValue(null),
      ...overrides,
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
  final h = FeatureHandle(tester, container, router, ad, demoDb);
  await h.settle(20);
  return h;
}

DioException offline() => DioException(
  requestOptions: RequestOptions(),
  type: DioExceptionType.connectionError,
);

/// Ekrandaki tüm düz metinler (hata ayıklama ve içerik denetimi için).
List<String> allTexts(WidgetTester t) => [
  for (final w in t.widgetList<Text>(find.byType(Text)))
    if (w.data != null) w.data!,
];

/// Alt sınıfları da (ör. `FilledButton.tonalIcon`) kapsayan düğme bulucu.
Finder buttonText<T extends Widget>(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is T),
  matching: find.text(label),
);

Future<void> tapVisible(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
}
