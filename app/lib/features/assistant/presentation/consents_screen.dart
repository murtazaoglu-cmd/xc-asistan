// Rızalar: verilen aydınlatma onayları ve geri çekme.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/formatters.dart';
import '../application/assistant_providers.dart';
import '../data/assistant_repository.dart';
import 'widgets/assistant_ui.dart';

class ConsentsScreen extends ConsumerWidget {
  const ConsentsScreen({super.key});

  Future<void> _withdraw(BuildContext context, WidgetRef ref, String id) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Rızayı geri çek',
      message: 'Geri çekince yeni yazışma içe aktarılamaz. Mevcut veriyi müşteri kartından silebilirsiniz.',
      confirmLabel: 'Geri çek',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(assistantRepositoryProvider).withdrawConsent(id);
      ref.invalidate(consentsProvider);
    } on Object catch (e) {
      if (context.mounted) toast(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(consentsProvider);
    return AppScaffold(
      title: 'Rızalar',
      showMenuButton: false,
      body: async.when(
        loading: () => const SkeletonList(),
        error: (e, _) => FillRefresh(
          onRefresh: () => ref.refresh(consentsProvider.future),
          child: ErrorState(
            message: errorText(e),
            onRetry: () => ref.invalidate(consentsProvider),
          ),
        ),
        data: (items) => items.isEmpty
            ? FillRefresh(
                onRefresh: () => ref.refresh(consentsProvider.future),
                child: const EmptyState(
                  icon: Icons.verified_user_outlined,
                  title: 'Kayıtlı rıza yok',
                  message: 'Yazışma içe aktarırken verdiğiniz onaylar burada listelenir.',
                ),
              )
            : PullToRefresh(
                onRefresh: () => ref.refresh(consentsProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.all(Space.lg),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                  itemBuilder: (_, i) {
                    final c = items[i];
                    return SectionCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.typeLabel,
                                  style: context.text.titleSmall,
                                ),
                                Text(
                                  c.active
                                      ? 'Verildi${c.givenAt == null ? '' : ': ${Fmt.dateTime(c.givenAt!)}'}'
                                      : 'Geri çekildi: ${Fmt.dateTime(c.withdrawnAt!)}',
                                  style: context.text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (c.active)
                            TextButton(
                              onPressed: () => _withdraw(context, ref, c.id),
                              child: const Text('Geri çek'),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
