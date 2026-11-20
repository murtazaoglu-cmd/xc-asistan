import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/util/money.dart';
import 'presentation/invoice_detail_screen.dart';
import 'presentation/invoice_form_screen.dart';
import 'presentation/invoices_vat_screen.dart';
import 'presentation/schedule_wizard_screen.dart';

/// Bu feature'ın rotaları (app_router.dart tarafından dala eklenir).
/// Rol koruması `RouteGuard` (`/invoices-vat` altındaki tüm yollar: personel/saha yönlenir).
/// Sıra önemli: sabit yollar (`new`, `plan/new`) `:id`'den ÖNCE gelir.
final List<RouteBase> invoicesVatRoutes = <RouteBase>[
  GoRoute(
    path: Routes.invoicesVat,
    builder: (context, state) => InvoicesVatScreen(
      initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
    ),
    routes: <RouteBase>[
      GoRoute(
        path: 'new',
        builder: (context, state) => const InvoiceFormScreen(),
      ),
      GoRoute(
        path: 'plan/new',
        builder: (context, state) {
          final q = state.uri.queryParameters;
          final kurus = int.tryParse(q['total'] ?? '');
          return ScheduleWizardScreen(
            projectId: q['projectId'],
            projectLabel: q['label'],
            initialTotal: kurus == null ? null : Money.fromKurus(kurus),
          );
        },
      ),
      GoRoute(
        path: ':id',
        builder: (context, state) =>
            InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
        routes: <RouteBase>[
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                InvoiceFormScreen(invoiceId: state.pathParameters['id']),
          ),
        ],
      ),
    ],
  ),
];
