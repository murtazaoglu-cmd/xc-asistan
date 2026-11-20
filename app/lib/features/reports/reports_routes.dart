import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'presentation/reports_screen.dart';

/// Bu feature'ın rotaları (app_router.dart tarafından dala eklenir).
final List<RouteBase> reportsRoutes = <RouteBase>[
  GoRoute(
    path: Routes.reports,
    builder: (context, state) => const ReportsScreen(),
    routes: <RouteBase>[],
  ),
];
