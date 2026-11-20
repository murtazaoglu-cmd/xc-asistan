// Müşteri silme: onay → listeden gizle → geri al süresi → gerçek DELETE.
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/ui/ui.dart';
import '../data/customer_models.dart';
import '../data/customers_repository.dart';

abstract final class CustomerActions {
  static Future<void> deleteWithUndo(BuildContext context, Customer c) async {
    final container = ProviderScope.containerOf(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final terms = container.read(brandProfileProvider).terms;
    final what = terms.customer.toLowerCase();
    final ok = await ConfirmDialog.show(
      context,
      title: '${c.displayName} silinsin mi?',
      message: c.isOfferDerived
          ? 'Bu $what ${terms.offer.toLowerCase()} kaynaklı olduğundan silinemeyebilir. Yalnız elle eklenen kayıtlar silinir.'
          : 'Yalnız bu $what kaydı silinir. İşlem birkaç saniye sonra kesinleşir; süre dolmadan geri alabilirsiniz.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!ok || !context.mounted) return;

    final key = c.phoneKey;
    final pending = container.read(pendingCustomerDeletesProvider.notifier);
    final repo = container.read(customersRepositoryProvider);
    pending.add(key);
    // Önce bildirimi kur (senkron), sonra ekrandan çık.
    UndoSnackbar.deferred(
      context,
      message: '${c.displayName} silindi',
      onUndo: () => pending.remove(key),
      onCommit: () async {
        try {
          await repo.delete(key);
          container.invalidate(customerListProvider);
          try {
            await container.read(customerListProvider.future);
          } catch (_) {}
          // Tekliften türeyen müşteri sunucuda sessizce silinmez: hâlâ varsa bildir.
          Customer? still;
          try {
            still = await repo.findByPhone(c.phoneKey);
          } catch (_) {}
          pending.remove(key);
          if (still != null) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  '${c.displayName} ${terms.offer.toLowerCase()} kaynaklı olduğu için silinemedi.',
                ),
              ),
            );
          }
        } catch (e) {
          pending.remove(key);
          messenger.showSnackBar(
            SnackBar(content: Text(AppException.from(e).message)),
          );
        }
      },
    );
    if (router.canPop()) router.pop();
  }
}
