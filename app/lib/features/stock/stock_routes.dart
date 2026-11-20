import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'presentation/stock_form_screen.dart';
import 'presentation/stock_screen.dart';

abstract final class StockRoutes {
  static const create = '${Routes.stock}/new';
  static String edit(String id) => '${Routes.stock}/$id';
}

/// Bu feature'ın rotaları (app_router.dart tarafından dala eklenir).
/// "new" sabit yolu `:id` desenden ÖNCE gelir.
final List<RouteBase> stockRoutes = <RouteBase>[
  GoRoute(
    path: Routes.stock,
    builder: (context, state) => const StockScreen(),
    routes: <RouteBase>[
      GoRoute(
        path: 'new',
        builder: (context, state) => const StockFormScreen(),
      ),
      GoRoute(
        path: ':id',
        builder: (context, state) =>
            StockFormScreen(id: state.pathParameters['id']),
      ),
    ],
  ),
];
