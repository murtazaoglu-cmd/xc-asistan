// Vergi takvimi sekmesi: yaklaşan öğeler (gün sayacı), tamamlandı işareti (cihazda),
// "doğrulanmadı" rozeti, kendi hatırlatmalarını ekle/düzenle/sil (admin/muhasebe; ortak okur).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../data/invoices_vat_errors.dart';
import '../data/invoices_vat_models.dart';
import '../data/invoices_vat_providers.dart';
import '../data/invoices_vat_repository.dart';
import '../data/invoices_vat_services.dart';
import 'inv_widgets.dart';

class TaxCalendarTab extends ConsumerWidget {
  const TaxCalendarTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(taxCalendarProvider);
    final done = ref.watch(taxDoneProvider);
    final canEdit =
        ref.watch(invoicesVatAccessProvider)?.canEditTaxCalendar ?? false;

    return PullToRefresh(
      onRefresh: () async {
        ref.invalidate(taxCalendarProvider);
        try {
          await ref.read(taxCalendarProvider.future);
        } catch (_) {}
      },
      child: async.when(
        loading: () => const SkeletonList(itemCount: 5, itemHeight: 88),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 360,
              child: ErrorState(
                error: e,
                onRetry: () => ref.invalidate(taxCalendarProvider),
              ),
            ),
          ],
        ),
        data: (cal) {
          final now = Ist.now();
          final open = <TaxItem>[];
          final finished = <TaxItem>[];
          for (final it in cal.items) {
            (done.contains(it.doneKey) ? finished : open).add(it);
          }
          int cmp(TaxItem a, TaxItem b) {
            final x = a.dueDate, y = b.dueDate;
            if (x == null || y == null) return x == null ? 1 : -1;
            return x.compareTo(y);
          }

          open.sort(cmp);
          finished.sort(cmp);
          if (cal.items.isEmpty) {
            return PullToRefresh.fill(
              onRefresh: () async => ref.invalidate(taxCalendarProvider),
              child: EmptyState(
                icon: Icons.event_available_outlined,
                title: 'Yaklaşan vergi tarihi yok',
                message: 'Takvim boş. Kendi hatırlatmanızı ekleyebilirsiniz.',
                actionLabel: canEdit ? 'Hatırlatma ekle' : null,
                onAction: canEdit
                    ? () => showTaxItemDialog(context, ref)
                    : null,
              ),
            );
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              96,
            ),
            children: [
              DisclaimerNote(
                cal.disclaimer ?? 'Tarihler bilgilendirme amaçlıdır. Resmî takvimi ve mali müşavirinizi esas alın.',
              ),
              if (cal.needsConfirmationCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(
                    '${cal.needsConfirmationCount} tarih doğrulanmadı.',
                    key: const Key('unverified_count'),
                    style: context.text.bodySmall?.copyWith(
                      color: context.xc.warning,
                    ),
                  ),
                ),
              const SizedBox(height: Space.md),
              for (final it in open)
                TaxItemCard(item: it, now: now, done: false, canEdit: canEdit),
              if (finished.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: Space.lg,
                    bottom: Space.sm,
                  ),
                  child: Text('Tamamlananlar', style: context.text.titleSmall),
                ),
                for (final it in finished)
                  TaxItemCard(item: it, now: now, done: true, canEdit: canEdit),
              ],
            ],
          );
        },
      ),
    );
  }
}

class TaxItemCard extends ConsumerWidget {
  const TaxItemCard({
    super.key,
    required this.item,
    required this.now,
    required this.done,
    required this.canEdit,
  });
  final TaxItem item;
  final DateTime now;
  final bool done;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = item.effectiveDays(now);
    final urgent = !done && days != null && days <= 3;
    final soon = !done && days != null && days <= 7;
    final tone = done
        ? StatusTone.success
        : urgent
        ? StatusTone.danger
        : soon
        ? StatusTone.warning
        : StatusTone.info;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Opacity(
                  opacity: done ? 0.6 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: context.text.titleSmall?.copyWith(
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (item.periodLabel != null)
                        Text(item.periodLabel!, style: context.text.bodySmall),
                      const SizedBox(height: Space.xs),
                      Row(
                        children: [
                          const Icon(Icons.event_outlined, size: Sizes.iconSm),
                          const SizedBox(width: Space.xs),
                          Text(
                            DateText.format(
                              item.dueDate,
                              DateTextMode.dateWeekday,
                            ),
                            style: context.text.bodyMedium,
                          ),
                        ],
                      ),
                      if (item.shifted)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Text(
                            item.shiftReasons.isEmpty
                                ? 'Tatil/hafta sonu nedeniyle kaydırıldı.'
                                : item.shiftReasons.join(' '),
                            style: context.text.bodySmall,
                          ),
                        ),
                      const SizedBox(height: Space.sm),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusChip(
                            label: done
                                ? 'Tamamlandı'
                                : item.countdownLabel(now),
                            tone: tone,
                            icon: done
                                ? Icons.check_circle_outline
                                : Icons.timer_outlined,
                          ),
                          if (item.custom)
                            const StatusChip(
                              label: 'Kendi hatırlatmam',
                              icon: Icons.person_outline,
                            ),
                          ConfirmBadge(item.confirmation, compact: true),
                        ],
                      ),
                      if (item.note != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Text(
                            item.note!,
                            style: context.text.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Column(
                children: [
                  IconButton(
                    key: Key('done_${item.key}'),
                    tooltip: done
                        ? 'Tamamlandı işaretini kaldır'
                        : 'Tamamlandı işaretle',
                    constraints: const BoxConstraints(
                      minWidth: Sizes.minTouch,
                      minHeight: Sizes.minTouch,
                    ),
                    icon: Icon(
                      done ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: done ? context.xc.success : null,
                    ),
                    onPressed: () =>
                        ref.read(taxDoneProvider.notifier).setDone(item, !done),
                  ),
                  if (canEdit && item.custom)
                    PopupMenuButton<String>(
                      tooltip: 'Hatırlatma işlemleri',
                      constraints: const BoxConstraints(
                        minWidth: Sizes.minTouch,
                      ),
                      onSelected: (v) async {
                        if (v == 'edit') {
                          await showTaxItemDialog(context, ref, existing: item);
                        } else if (v == 'delete') {
                          await _delete(context, ref);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                        PopupMenuItem(value: 'delete', child: Text('Sil')),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final id = item.id ?? item.key;
    final go = await ConfirmDialog.show(
      context,
      title: 'Hatırlatma silinsin mi?',
      message: item.title,
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!go) return;
    try {
      await ref.read(invoicesVatRepositoryProvider).deleteTaxItem(id);
      ref.invalidate(taxCalendarProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(InvoicesVatErrors.message(e, InvoicesVatOp.delete)),
          ),
        );
      }
    }
  }
}

/// Kendi hatırlatmanı ekle / düzenle (admin/muhasebe).
Future<void> showTaxItemDialog(
  BuildContext context,
  WidgetRef ref, {
  TaxItem? existing,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _TaxItemDialog(existing: existing),
  );
  if (saved ?? false) ref.invalidate(taxCalendarProvider);
}

class _TaxItemDialog extends ConsumerStatefulWidget {
  const _TaxItemDialog({this.existing});
  final TaxItem? existing;

  @override
  ConsumerState<_TaxItemDialog> createState() => _TaxItemDialogState();
}

class _TaxItemDialogState extends ConsumerState<_TaxItemDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late String? _date = widget.existing?.dueDate == null
      ? null
      : dayKey(widget.existing!.dueDate!);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_date == null) {
      setState(() => _error = 'Tarih seçin.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(invoicesVatRepositoryProvider);
    try {
      final ex = widget.existing;
      if (ex == null) {
        await repo.createTaxItem(
          title: _title.text,
          dueDate: _date!,
          note: _note.text,
        );
      } else {
        await repo.updateTaxItem(
          ex.id ?? ex.key,
          title: _title.text,
          dueDate: _date,
          note: _note.text,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = InvoicesVatErrors.message(e, InvoicesVatOp.save);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Hatırlatma ekle' : 'Hatırlatmayı düzenle',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('tax_title'),
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Başlık'),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Başlık gerekli.';
                  if (s.length > 120)
                    return 'Başlık en çok 120 karakter olabilir.';
                  return null;
                },
              ),
              const SizedBox(height: Space.md),
              DayField(
                label: 'Tarih',
                value: _date,
                onChanged: (v) => setState(() => _date = v),
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _note,
                maxLines: 2,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                ),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: context.colors.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const Key('tax_save'),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Kaydet'),
        ),
      ],
    );
  }
}
