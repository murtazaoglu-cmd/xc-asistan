// Para rota tanımları (app_router bağımlılığı YOK: testte kendi gezgin anahtarıyla kurulabilir).
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'data/finance_models.dart';
import 'finance_nav.dart';
import 'presentation/expense_form_screen.dart';
import 'presentation/finance_screen.dart';
import 'presentation/payment_form_screen.dart';
import 'presentation/receivables_section.dart';
import 'presentation/recurring_form_screen.dart';

/// Rota ağacı. [parentKey] verilirse form ekranları o gezginde (kabuğun ÜSTÜNDE) açılır.
List<RouteBase> buildFinanceRoutes({GlobalKey<NavigatorState>? parentKey}) =>
    <RouteBase>[
      GoRoute(
        path: Routes.finance,
        builder: (context, state) => const FinanceScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'receivables',
            name: FinanceRouteNames.receivables,
            parentNavigatorKey: parentKey,
            builder: (context, state) => const ReceivablesScreen(),
          ),
          GoRoute(
            path: 'payments/new',
            name: FinanceRouteNames.addPayment,
            parentNavigatorKey: parentKey,
            builder: (context, state) => PaymentFormScreen(
              projectId: state.uri.queryParameters['projectId'],
            ),
          ),
          GoRoute(
            path: 'payments/:id/edit',
            name: FinanceRouteNames.editPayment,
            parentNavigatorKey: parentKey,
            builder: (context, state) => PaymentFormLoader(
              paymentId: state.pathParameters['id']!,
              initial: state.extra is Payment ? state.extra as Payment : null,
            ),
          ),
          GoRoute(
            path: 'expenses/new',
            name: FinanceRouteNames.addExpense,
            parentNavigatorKey: parentKey,
            builder: (context, state) => ExpenseFormScreen(
              projectId: state.uri.queryParameters['projectId'],
            ),
          ),
          GoRoute(
            path: 'expenses/:id/edit',
            name: FinanceRouteNames.editExpense,
            parentNavigatorKey: parentKey,
            builder: (context, state) => ExpenseFormLoader(
              expenseId: state.pathParameters['id']!,
              initial: state.extra is Expense ? state.extra as Expense : null,
            ),
          ),
          GoRoute(
            path: 'recurring/new',
            name: FinanceRouteNames.addRecurring,
            parentNavigatorKey: parentKey,
            builder: (context, state) => const RecurringFormScreen(),
          ),
          GoRoute(
            path: 'recurring/:id/edit',
            name: FinanceRouteNames.editRecurring,
            parentNavigatorKey: parentKey,
            builder: (context, state) => RecurringFormLoader(
              recurringId: state.pathParameters['id']!,
              initial: state.extra is RecurringExpense
                  ? state.extra as RecurringExpense
                  : null,
            ),
          ),
        ],
      ),
    ];
