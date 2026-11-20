// Sabit giderler sekmesi (A M O): liste, ekle/düzenle, "Bu ay uygula" (409 nazik).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/finance_errors.dart';
import '../data/finance_input.dart';
import '../data/finance_models.dart';
import '../data/finance_providers.dart';
import '../finance_nav.dart';
import 'finance_actions.dart';
import 'payments_tab.dart' show AsyncSection;

class RecurringTab extends ConsumerStatefulWidget {
  const RecurringTab({super.key});

  @override
  ConsumerState<RecurringTab> createState() => _RecurringTabState();
}

class _RecurringTabState extends ConsumerState<RecurringTab> {
  final Set<String> _busy = {};

  Future<void> _apply(RecurringExpense r) async {
    final controller = ref.read(financeControllerProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(r.id));
    try {
      final created = await controller.applyRecurring(r.id);
      if (!mounted) return;
      UndoSnackbar.show(
        context,
        message:
            '"${r.category}" bu aya eklendi (${r.amount.format(hideZeroKurus: true)})',
        onUndo: () => controller
            .removeExpense(created.id)
            .catchError((Object e) => showUndoFailure(messenger, e)),
      );
    } catch (e) {
      if (!mounted) return;
      // 409 hata değil, bilgidir: nazik ve nötr gösterilir.
      showFinanceMessage(
        messenger,
        FinanceErrors.message(e, FinanceOp.applyRecurring),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  Future<void> _toggle(RecurringExpense r, bool active) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(financeControllerProvider)
          .editRecurring(
            r.id,
            RecurringInput(
              category: r.category,
              amount: r.amount,
              scope: r.scope,
              note: r.note,
              active: active,
            ),
          );
    } catch (e) {
      showFinanceMessage(
        messenger,
        FinanceErrors.message(e, FinanceOp.saveRecurring),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hidden = ref.watch(pendingDeletesProvider);
    final terms = ref.watch(brandProfileProvider).terms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => FinanceNav.addRecurring(context),
          icon: const Icon(Icons.add),
          label: const Text('Sabit gider ekle'),
        ),
        const SizedBox(height: Space.md),
        AsyncSection<List<RecurringExpense>>(
          value: ref.watch(recurringProvider),
          onRetry: () => ref.invalidate(recurringProvider),
          builder: (all) {
            final items = all.where((r) => !hidden.contains(r.id)).toList();
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.event_repeat,
                title: 'Sabit gider yok',
                message: 'Kira, fatura gibi her ay tekrarlayan giderleri bir kez ekleyin; "Bu ay uygula" ile tek dokunuşla işleyin.',
              );
            }
            return Column(
              children: [
                for (final r in items)
                  _RecurringCard(
                    item: r,
                    label: FinanceCategories.label(terms, r.category),
                    busy: _busy.contains(r.id),
                    onApply: () => _apply(r),
                    onToggle: (v) => _toggle(r, v),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RecurringCard extends ConsumerWidget {
  const _RecurringCard({
    required this.item,
    required this.label,
    required this.busy,
    required this.onApply,
    required this.onToggle,
  });
  final RecurringExpense item;
  final String label;
  final bool busy;
  final VoidCallback onApply;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = item;
    final scheme = context.colors;
    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: context.text.titleSmall)),
                PopupMenuButton<String>(
                  tooltip: 'Sabit gider işlemleri',
                  onSelected: (v) {
                    if (v == 'edit') FinanceNav.editRecurring(context, r);
                    if (v == 'delete') deleteRecurringWithUndo(context, ref, r);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                    PopupMenuItem(value: 'delete', child: Text('Sil')),
                  ],
                ),
              ],
            ),
            Wrap(
              spacing: Space.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MoneyText(r.amount, style: context.text.titleMedium),
                    Text(' / ay', style: context.text.bodyMedium),
                  ],
                ),
                Text(
                  r.scope.label,
                  style: context.text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if ((r.note ?? '').isNotEmpty)
              Text(r.note!, style: context.text.bodySmall),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: (!r.active || busy) ? null : onApply,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.playlist_add_check),
                    label: const Text('Bu ay uygula'),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Semantics(
                  label: r.active ? 'Aktif' : 'Pasif',
                  child: Switch(value: r.active, onChanged: onToggle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
