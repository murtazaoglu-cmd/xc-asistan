// Ortak eylem yardımcıları: geri alınabilir silme, kapatma, bildirimler.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/ui/ui.dart';
import '../data/finance_errors.dart';
import '../data/finance_models.dart';
import '../data/finance_providers.dart';

/// Formu kapatır: geçmiş varsa geri, yoksa Para ekranına.
void closeFinanceForm(BuildContext context, [Object? result]) {
  if (context.canPop()) {
    context.pop(result);
  } else {
    context.go(Routes.finance);
  }
}

/// Ödemeyi "geri al" penceresiyle siler: kayıt listeden hemen gizlenir, gerçek DELETE
/// bildirim kapanınca gider (sözleşme §14: silme geri alınamaz).
void deletePaymentWithUndo(BuildContext context, WidgetRef ref, Payment p) {
  final controller = ref.read(financeControllerProvider);
  final pending = ref.read(pendingDeletesProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  pending.add(p.id);
  UndoSnackbar.deferred(
    context,
    message: '${p.amount.format(hideZeroKurus: true)} ödeme silindi',
    onUndo: () => pending.remove(p.id),
    onCommit: () async {
      try {
        await controller.removePayment(p.id);
      } catch (e) {
        showFinanceMessage(
          messenger,
          FinanceErrors.message(e, FinanceOp.delete),
        );
      } finally {
        pending.remove(p.id);
      }
    },
  );
}

void deleteExpenseWithUndo(BuildContext context, WidgetRef ref, Expense e) {
  final controller = ref.read(financeControllerProvider);
  final pending = ref.read(pendingDeletesProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  pending.add(e.id);
  UndoSnackbar.deferred(
    context,
    message: '${e.amount.format(hideZeroKurus: true)} gider silindi',
    onUndo: () => pending.remove(e.id),
    onCommit: () async {
      try {
        await controller.removeExpense(e.id);
      } catch (err) {
        showFinanceMessage(
          messenger,
          FinanceErrors.message(err, FinanceOp.delete),
        );
      } finally {
        pending.remove(e.id);
      }
    },
  );
}

void deleteRecurringWithUndo(
  BuildContext context,
  WidgetRef ref,
  RecurringExpense r,
) {
  final controller = ref.read(financeControllerProvider);
  final pending = ref.read(pendingDeletesProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  pending.add(r.id);
  UndoSnackbar.deferred(
    context,
    message: '"${r.category}" sabit gideri silindi',
    onUndo: () => pending.remove(r.id),
    onCommit: () async {
      try {
        await controller.removeRecurring(r.id);
      } catch (err) {
        showFinanceMessage(
          messenger,
          FinanceErrors.message(err, FinanceOp.delete),
        );
      } finally {
        pending.remove(r.id);
      }
    },
  );
}

/// Geri alma sırasında oluşan hatayı sessizce yutmak yerine bildirir.
void showUndoFailure(ScaffoldMessengerState messenger, Object error) {
  showFinanceMessage(
    messenger,
    'Geri alınamadı. ${FinanceErrors.message(error, FinanceOp.delete)}',
  );
}

/// Bildirim gösterir; öncekini hemen kapatır (ileti kuyrukta 8 sn beklemez).
void showFinanceMessage(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
