// Para modülünü DIŞARIDAN çağırma yardımcıları (rota adı + parametre). Yalnız go_router'a bağlıdır.
//
//   final saved = await FinanceNav.addPayment(context, projectId: id);   // true → kaydedildi
//   final saved = await FinanceNav.addExpense(context, projectId: id);   // projectId null → genel gider
//   ref.listen(financeChangesProvider, (_, _) => ...);                   // kayıtta kendi verini yenile
// Kayıtlı rota adları: FinanceRouteNames.addPayment ('finance.addPayment'), .addExpense ('finance.addExpense').
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'data/finance_models.dart';

abstract final class FinanceRouteNames {
  static const addPayment = 'finance.addPayment';
  static const editPayment = 'finance.editPayment';
  static const addExpense = 'finance.addExpense';
  static const editExpense = 'finance.editExpense';
  static const addRecurring = 'finance.addRecurring';
  static const editRecurring = 'finance.editRecurring';
  static const receivables = 'finance.receivables';
}

/// Çağrı yardımcıları (rota adı + parametre).
abstract final class FinanceNav {
  static const String receivablesPath = '${Routes.finance}/receivables';

  /// Ödeme ekleme ekranı. Dönüş: kaydedildiyse true.
  static Future<bool?> addPayment(BuildContext context, {String? projectId}) =>
      GoRouter.of(context).pushNamed<bool>(
        FinanceRouteNames.addPayment,
        queryParameters: {if (projectId != null) 'projectId': projectId},
      );

  /// Gider ekleme ekranı; [projectId] verilirse projeye bağlı gelir.
  static Future<bool?> addExpense(BuildContext context, {String? projectId}) =>
      GoRouter.of(context).pushNamed<bool>(
        FinanceRouteNames.addExpense,
        queryParameters: {if (projectId != null) 'projectId': projectId},
      );

  static Future<bool?> editPayment(BuildContext context, Payment p) =>
      GoRouter.of(context).pushNamed<bool>(
        FinanceRouteNames.editPayment,
        pathParameters: {'id': p.id},
        extra: p,
      );

  static Future<bool?> editExpense(BuildContext context, Expense e) =>
      GoRouter.of(context).pushNamed<bool>(
        FinanceRouteNames.editExpense,
        pathParameters: {'id': e.id},
        extra: e,
      );

  static Future<bool?> addRecurring(BuildContext context) =>
      GoRouter.of(context).pushNamed<bool>(FinanceRouteNames.addRecurring);

  static Future<bool?> editRecurring(
    BuildContext context,
    RecurringExpense r,
  ) => GoRouter.of(context).pushNamed<bool>(
    FinanceRouteNames.editRecurring,
    pathParameters: {'id': r.id},
    extra: r,
  );
}
