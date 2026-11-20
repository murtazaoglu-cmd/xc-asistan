import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/app.dart';
import 'package:xc_asistan/app_wiring.dart';
import 'package:xc_asistan/core/config/app_config.dart';
import 'package:xc_asistan/core/demo/demo_adapter.dart';
import 'package:xc_asistan/core/demo/demo_db.dart';
import 'package:xc_asistan/core/router/app_router.dart';
import 'package:xc_asistan/core/storage/token_store.dart';
import 'package:go_router/go_router.dart';

import 'fakes.dart';

class AppHandle {
  AppHandle(this.tester, this.container);
  final WidgetTester tester;
  final ProviderContainer container;
  GoRouter get router => container.read(routerProvider);
  String get location => router.state.uri.toString();

  /// Animasyonlu iskelet (sonsuz) yüzünden pumpAndSettle yerine kısa aralıklarla ilerler.
  Future<void> settle([int steps = 12]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> go(String path) async {
    router.go(path);
    await settle();
  }
}

/// Gerçek uygulamayı DEMO sahte API'siyle açar. [role] verilirse o rolün jetonu önceden
/// kayıtlıdır (oturum açık başlar); null ise girişsiz başlar.
Future<AppHandle> pumpXcApp(
  WidgetTester tester, {
  String? role,
  String initialLocation = '/today',
  Size? logicalSize,
}) async {
  tester.view.physicalSize = logicalSize ?? const Size(1080, 2200);
  tester.view.devicePixelRatio = logicalSize == null ? 3 : 1;
  addTearDown(tester.view.reset);
  final store = MemoryTokenStore()
    ..token = role == null ? null : 'demo-token-$role';
  final overrides = await baseOverrides(
    store: store,
    config: const AppConfig(demo: true, retryBaseDelay: Duration.zero),
  );
  final db = DemoDb(now: DateTime.utc(2026, 11, 20, 8, 0));
  final container = ProviderContainer(
    retry: noProviderRetry,
    overrides: [
      ...overrides,
      ...featureWiring,
      demoAdapterProvider.overrideWithValue(
        DemoHttpAdapter(db, latency: Duration.zero),
      ),
      initialLocationProvider.overrideWithValue(initialLocation),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const XcApp()),
  );
  final h = AppHandle(tester, container);
  await h.settle(20);
  return h;
}
