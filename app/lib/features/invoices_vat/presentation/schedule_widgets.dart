// Tahsilat planı satırı + satır eylemleri (ödendi, hatırlat, düzenle, sil) + yaşlandırma kartı.
// Hem Ödeme Planı sekmesi hem de dışa açılan PaymentScheduleSection bunları kullanır.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/money.dart';
import '../data/invoices_vat_errors.dart';
import '../data/invoices_vat_input.dart';
import '../data/invoices_vat_models.dart';
import '../data/invoices_vat_providers.dart';
import '../data/invoices_vat_repository.dart';
import 'inv_widgets.dart';
import 'invoices_actions.dart';

/// Plan satırı durum rozeti.
StatusChip scheduleStatusChip(ScheduleItem s, [DateTime? now]) {
  if (s.isPaid)
    return const StatusChip(
      label: 'Ödendi',
      tone: StatusTone.success,
      icon: Icons.check_circle_outline,
    );
  if (s.isCancelled)
    return const StatusChip(
      label: 'İptal',
      tone: StatusTone.danger,
      icon: Icons.block,
    );
  if (s.isOverdue(now)) {
    return StatusChip(
      label: 'Gecikti · ${s.overdueDays(now)} gün',
      tone: StatusTone.danger,
      icon: Icons.warning_amber,
    );
  }
  final d = s.dueDate == null
      ? null
      : Ist.dayDiff(now ?? Ist.now(), s.dueDate!);
  if (d != null && d <= 7) {
    return StatusChip(
      label: d == 0 ? 'Bugün vade' : '$d gün kaldı',
      tone: StatusTone.warning,
      icon: Icons.schedule,
    );
  }
  return const StatusChip(
    label: 'Bekliyor',
    tone: StatusTone.info,
    icon: Icons.hourglass_empty,
  );
}

class ScheduleRowTile extends ConsumerWidget {
  const ScheduleRowTile({
    super.key,
    required this.item,
    this.showWho = false,
    this.readOnly = false,
  });
  final ScheduleItem item;

  /// Proje/müşteri adını satırda göster (gruplanmamış listelerde).
  final bool showWho;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = item;
    final overdue = s.isOverdue();
    final subtitle = [
      s.kind?.label ?? s.kindRaw,
      if (s.method != null) s.method!,
      if (s.instrumentNo != null) 'No: ${s.instrumentNo}',
      if (s.bank != null) s.bank!,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: Space.sm),
      decoration: BoxDecoration(
        color: overdue
            ? context.colors.errorContainer.withValues(alpha: 0.35)
            : context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: overdue ? context.colors.error : context.colors.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.sm,
          Space.xs,
          Space.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showWho)
                    Text(s.displayWho, style: context.text.titleSmall),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          DateText.format(s.dueDate, DateTextMode.date),
                          style: context.text.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      MoneyText(s.amount, style: context.text.titleSmall),
                    ],
                  ),
                  Text(
                    subtitle,
                    style: context.text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.xs),
                  scheduleStatusChip(s),
                ],
              ),
            ),
            if (!readOnly && s.isPending)
              IconButton(
                key: Key('pay_${s.id}'),
                tooltip: 'Ödendi işaretle',
                constraints: const BoxConstraints(
                  minWidth: Sizes.minTouch,
                  minHeight: Sizes.minTouch,
                ),
                icon: const Icon(Icons.check_circle_outline),
                onPressed: () => markSchedulePaidFlow(context, ref, s),
              ),
            if (!readOnly)
              PopupMenuButton<String>(
                key: Key('menu_${s.id}'),
                tooltip: 'Satır işlemleri',
                constraints: const BoxConstraints(minWidth: Sizes.minTouch),
                onSelected: (v) {
                  switch (v) {
                    case 'remind':
                      showReminderSheet(
                        context,
                        scheduleId: s.id,
                        phone: s.customerPhone,
                        name: s.displayWho,
                        daysOverdue: s.overdueDays(),
                      );
                    case 'edit':
                      showScheduleEditSheet(context, ref, s);
                    case 'delete':
                      deleteScheduleFlow(context, ref, s);
                  }
                },
                itemBuilder: (_) => [
                  if (s.isPending)
                    const PopupMenuItem(
                      value: 'remind',
                      child: Text('WhatsApp\'ta hatırlat'),
                    ),
                  const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                  const PopupMenuItem(value: 'delete', child: Text('Sil')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> markSchedulePaidFlow(
  BuildContext context,
  WidgetRef ref,
  ScheduleItem s,
) async {
  final repo = ref.read(invoicesVatRepositoryProvider);
  final ok = await showMarkPaidSheet(
    context,
    title: s.displayWho,
    amount: s.amount,
    canCreatePayment: s.projectId != null,
    initialMethod: s.methodEnum,
    onConfirm: (date, method, createPayment) => repo.markSchedulePaid(
      s.id,
      paidAt: date,
      createPayment: createPayment,
      method: method,
    ),
  );
  if (ok) {
    invalidateInvoicesVatW(ref);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ödendi olarak işaretlendi.')),
      );
    }
  }
}

Future<void> deleteScheduleFlow(
  BuildContext context,
  WidgetRef ref,
  ScheduleItem s,
) async {
  final go = await ConfirmDialog.show(
    context,
    title: 'Plan satırı silinsin mi?',
    message:
        '${DateText.format(s.dueDate, DateTextMode.date)} · ${s.amount.format()}',
    confirmLabel: 'Sil',
    destructive: true,
  );
  if (!go) return;
  try {
    await ref.read(invoicesVatRepositoryProvider).deleteScheduleItem(s.id);
    invalidateInvoicesVatW(ref);
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

// ================================================================ Satır düzenleme

Future<void> showScheduleEditSheet(
  BuildContext context,
  WidgetRef ref,
  ScheduleItem s,
) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ScheduleEditSheet(item: s),
  );
  if (ok ?? false) invalidateInvoicesVatW(ref);
}

class _ScheduleEditSheet extends ConsumerStatefulWidget {
  const _ScheduleEditSheet({required this.item});
  final ScheduleItem item;

  @override
  ConsumerState<_ScheduleEditSheet> createState() => _ScheduleEditSheetState();
}

class _ScheduleEditSheetState extends ConsumerState<_ScheduleEditSheet> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.item.amount.toApiString().replaceAll('.', ','),
  );
  late final _no = TextEditingController(text: widget.item.instrumentNo ?? '');
  late final _bank = TextEditingController(text: widget.item.bank ?? '');
  late final _note = TextEditingController(text: widget.item.note ?? '');
  late String? _due = widget.item.dueDate == null
      ? null
      : dayKey(widget.item.dueDate!);
  late ScheduleMethod? _method = widget.item.methodEnum;
  late ScheduleKind _kind = widget.item.kind ?? ScheduleKind.taksit;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_amount, _no, _bank, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_due == null) {
      setState(() => _error = 'Vade tarihi seçin.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = widget.item;
      await ref
          .read(invoicesVatRepositoryProvider)
          .updateScheduleItem(
            s.id,
            ScheduleInput(
              amount: Money.parseUserInput(_amount.text)!,
              dueDate: _due!,
              projectId: s.projectId,
              offerId: s.offerId,
              invoiceId: s.invoiceId,
              kind: _kind,
              method: _method,
              instrumentNo: _no.text,
              bank: _bank.text,
              note: _note.text,
            ),
          );
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
    final instrument = _method?.isInstrument ?? false;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        MediaQuery.viewInsetsOf(context).bottom + Space.lg,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Plan satırını düzenle', style: context.text.titleLarge),
              const SizedBox(height: Space.lg),
              MoneyField(controller: _amount, label: 'Tutar'),
              const SizedBox(height: Space.md),
              DayField(
                label: 'Vade',
                value: _due,
                onChanged: (v) => setState(() => _due = v),
              ),
              const SizedBox(height: Space.md),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final k in ScheduleKind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final m in ScheduleMethod.values)
                    ChoiceChip(
                      label: Text(m.label),
                      selected: _method == m,
                      onSelected: (s) => setState(() => _method = s ? m : null),
                    ),
                ],
              ),
              if (instrument ||
                  _kind == ScheduleKind.cek ||
                  _kind == ScheduleKind.senet) ...[
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: _no,
                  decoration: InputDecoration(
                    labelText:
                        _kind == ScheduleKind.senet ||
                            _method == ScheduleMethod.senet
                        ? 'Senet no'
                        : 'Çek no',
                  ),
                ),
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: _bank,
                  decoration: const InputDecoration(labelText: 'Banka'),
                ),
              ],
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _note,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Not'),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: context.colors.error)),
              const SizedBox(height: Space.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('schedule_edit_save'),
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Kaydet'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================ Yaşlandırma

class AgingCard extends ConsumerWidget {
  const AgingCard({super.key, this.projectId});
  final String? projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(agingProvider(projectId));
    return async.when(
      loading: () => const SkeletonBox(height: 150, radius: Radii.card),
      error: (e, _) => SectionCard(
        title: 'Tahsilat yaşlandırma',
        child: Row(
          children: [
            Expanded(
              child: Text(InvoicesVatErrors.message(e, InvoicesVatOp.load)),
            ),
            TextButton(
              onPressed: () => ref.invalidate(agingProvider(projectId)),
              child: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
      data: (r) => SectionCard(
        key: const Key('aging_card'),
        title: 'Tahsilat yaşlandırma',
        trailing: r.overdueCount > 0
            ? StatusChip(
                label: '${r.overdueCount} gecikmiş',
                tone: StatusTone.danger,
                icon: Icons.warning_amber,
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: MetricBox(
                    label: 'Toplam alacak',
                    value: r.total.format(),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: MetricBox(
                    label: 'Vadesi geçen',
                    value: r.overdue.format(),
                    color: r.overdue.isPositive ? context.colors.error : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final k in agingBucketKeys)
                  _BucketChip(
                    bucketKey: k,
                    bucket: r.bucket(k),
                    onTap: () => _showBucket(context, k, r.bucket(k)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showBucket(BuildContext context, String key, AgingBucket b) {
    if (b.items.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BucketSheet(bucketKey: key, bucket: b),
    );
  }
}

class _BucketChip extends StatelessWidget {
  const _BucketChip({
    required this.bucketKey,
    required this.bucket,
    required this.onTap,
  });
  final String bucketKey;
  final AgingBucket bucket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final late = bucketKey != 'notDue' && bucket.count > 0;
    return Semantics(
      button: true,
      label:
          '${agingBucketLabel(bucketKey)}: ${bucket.count} kayıt, ${bucket.total.format()}',
      excludeSemantics: true,
      child: InkWell(
        key: Key('bucket_$bucketKey'),
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minWidth: 96,
            minHeight: Sizes.minTouch,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            color: late
                ? context.colors.errorContainer.withValues(alpha: 0.4)
                : context.colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(agingBucketLabel(bucketKey), style: context.text.bodySmall),
              Text(
                bucket.total.format(hideZeroKurus: true),
                style: context.text.titleSmall,
              ),
              Text('${bucket.count} kayıt', style: context.text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _BucketSheet extends StatelessWidget {
  const _BucketSheet({required this.bucketKey, required this.bucket});
  final String bucketKey;
  final AgingBucket bucket;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          shrinkWrap: true,
          children: [
            Text(agingBucketLabel(bucketKey), style: context.text.titleLarge),
            Text(
              '${bucket.count} kayıt · ${bucket.total.format()}',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: Space.md),
            for (final it in bucket.items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                minVerticalPadding: Space.sm,
                title: Text(it.displayWho),
                subtitle: Text(
                  '${DateText.format(it.dueDate, DateTextMode.date)}'
                  '${(it.daysOverdue ?? 0) > 0 ? ' · ${it.daysOverdue} gün gecikti' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MoneyText(it.amount, style: context.text.titleSmall),
                    if (it.scheduleId != null || it.invoiceId != null)
                      IconButton(
                        tooltip: 'WhatsApp\'ta hatırlat',
                        constraints: const BoxConstraints(
                          minWidth: Sizes.minTouch,
                          minHeight: Sizes.minTouch,
                        ),
                        icon: const Icon(Icons.chat_outlined),
                        onPressed: () => showReminderSheet(
                          context,
                          scheduleId: it.scheduleId,
                          invoiceId: it.scheduleId == null
                              ? it.invoiceId
                              : null,
                          phone: it.customerPhone,
                          name: it.displayWho,
                          daysOverdue: it.daysOverdue ?? 0,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
