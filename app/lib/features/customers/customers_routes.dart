import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'presentation/customer_detail_screen.dart';
import 'presentation/customer_form_screen.dart';
import 'presentation/customers_screen.dart';

/// Müşteri alt rotaları (çekirdek `Routes`'a dokunmadan bu feature'da tanımlı).
abstract final class CustomerRoutes {
  static const create = '${Routes.customers}/new';
  static String edit(String phoneKey) => '${Routes.customers}/$phoneKey/edit';
}

/// Bu feature'ın rotaları (app_router.dart tarafından dala eklenir).
/// Not: "new" sabit yolu `:phoneKey` desenden ÖNCE gelmelidir.
final List<RouteBase> customersRoutes = <RouteBase>[
  GoRoute(
    path: Routes.customers,
    builder: (context, state) => const CustomersScreen(),
    routes: <RouteBase>[
      GoRoute(
        path: 'new',
        builder: (context, state) => const CustomerFormScreen(),
      ),
      GoRoute(
        path: Routes.customerPattern,
        builder: (context, state) =>
            CustomerDetailScreen(phoneKey: state.pathParameters['phoneKey']!),
        routes: <RouteBase>[
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                CustomerFormScreen(phoneKey: state.pathParameters['phoneKey']),
          ),
        ],
      ),
    ],
  ),
];
