// GoRouter kurulumu. Feature rotaları her feature'ın kendi `<feature>_routes.dart`
// dosyasından gelir; bu dosyaya YENİ ekran eklenmez (yalnız dal/kök değişirse).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/appointments/appointments_routes.dart';
import '../../features/assistant/assistant_routes.dart';
import '../../features/auth/auth_routes.dart';
import '../../features/customers/customers_routes.dart';
import '../../features/finance/finance_routes.dart';
import '../../features/home/home_routes.dart';
import '../../features/invoices_vat/invoices_vat_routes.dart';
import '../../features/jobs/jobs_routes.dart';
import '../../features/more/more_routes.dart';
import '../../features/reports/reports_routes.dart';
import '../../features/settings/settings_routes.dart';
import '../../features/stock/stock_routes.dart';
import '../api/health_service.dart';
import '../auth/session.dart';
import 'redirect.dart';
import 'shell_scaffold.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Test/özel başlangıç için: initialLocation override edilebilir.
final initialLocationProvider = Provider<String>((ref) => '/today');

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(updateRequirementProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: ref.read(initialLocationProvider),
    refreshListenable: refresh,
    redirect: (context, state) => computeRedirect(
      session: ref.read(sessionProvider),
      uri: state.uri,
      update:
          ref.read(updateRequirementProvider).value ?? UpdateRequirement.none,
    ),
    routes: [
      ...authRoutes, // /splash, /login, /update-required
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            ShellScaffold(location: state.uri.path, navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: homeRoutes), // 0 Bugün
          StatefulShellBranch(routes: jobsRoutes), // 1 İşler
          StatefulShellBranch(routes: assistantRoutes), // 2 Asistan
          StatefulShellBranch(routes: customersRoutes), // 3 Müşteriler
          StatefulShellBranch(routes: financeRoutes), // 4 Para
          StatefulShellBranch(
            routes: [
              // 5 Seyrek ekranlar (sol üst menü)
              ...appointmentsRoutes,
              ...stockRoutes,
              ...reportsRoutes,
              ...invoicesVatRoutes,
              ...settingsRoutes,
              ...moreRoutes,
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
