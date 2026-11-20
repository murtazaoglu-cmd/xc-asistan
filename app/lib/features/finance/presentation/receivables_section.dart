// Alacak takibi: proje bazlı kalan bakiye, vadesi geçenler vurgulu, "WhatsApp'ta hatırlat".
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/formatters.dart';
import '../../../core/util/money.dart';
import '../data/finance_calc.dart';
import '../data/finance_messages.dart';
import '../data/finance_providers.dart';
import '../data/finance_repository.dart';
import '../finance_nav.dart';
import 'finance_actions.dart';
import 'payment_schedule_section.dart';

/// Özet sekmesindeki "Alacaklar" kartı (ilk [limit] satır + "Tümünü gör").
class ReceivablesSection extends ConsumerWidget {
  const ReceivablesSection({super.key, this.limit = 5});
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receivablesProvider);
    return SectionCard(
      title: 'Alacaklar',
      trailing: async.maybeWhen(
        data: (l) => l.isEmpty
            ? null
            : MoneyText(
                FinanceCalc.totalReceivable(l),
                hideZeroKurus: true,
                style: context.text.titleMedium,
              ),
        orElse: () => null,
      ),
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.sm,
      ),
      child: async.when(
        loading: () => const Column(
          children: [
            SkeletonBox(height: 56),
            SizedBox(height: Space.sm),
            SkeletonBox(height: 56),
          ],
        ),
        error: (e, _) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 200),
          child: ErrorState(
            error: e,
            onRetry: () => ref.invalidate(allProjectsProvider),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: context.xc.success),
                  const SizedBox(width: Space.sm),
                  const Expanded(child: Text('Bekleyen alacak yok.')),
                ],
              ),
            );
          }
          final shown = items.take(limit).toList();
          return Column(
            children: [
              for (final r in shown) ReceivableTile(item: r),
              if (items.length > limit)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push(FinanceNav.receivablesPath),
                    child: Text('Tümünü gör (${items.length})'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Tüm alacaklar (tam ekran).
class ReceivablesScreen extends ConsumerWidget {
  const ReceivablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receivablesProvider);
    return AppScaffold(
      title: 'Alacaklar',
      showMenuButton: false,
      body: AsyncValueView<List<Receivable>>(
        value: async,
        onRetry: () => ref.invalidate(allProjectsProvider),
        isEmpty: (l) => l.isEmpty,
        empty: PullToRefresh.fill(
          onRefresh: () => ref.refresh(allProjectsProvider.future),
          child: const EmptyState(
            icon: Icons.check_circle_outline,
            title: 'Bekleyen alacak yok',
            message: 'Tüm projelerin bakiyesi tahsil edilmiş.',
          ),
        ),
        data: (items) => PullToRefresh(
          onRefresh: () => ref.refresh(allProjectsProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Space.lg),
            children: [
              SectionCard(
                title: 'Toplam alacak',
                trailing: MoneyText(
                  FinanceCalc.totalReceivable(items),
                  style: context.text.titleLarge,
                ),
                child: Text(
                  '${items.length} proje · ${items.where((e) => e.isOverdue).length} vadesi geçmiş',
                  style: context.text.bodyMedium,
                ),
              ),
              const SizedBox(height: Space.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Column(
                    children: [for (final r in items) ReceivableTile(item: r)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vadesi geçti işareti: renk + ikon + metin.
class OverdueChip extends StatelessWidget {
  const OverdueChip({super.key, required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 14, color: scheme.onErrorContainer),
          const SizedBox(width: Space.xs),
          Flexible(
            child: Text(
              'Vadesi geçti · $days gün',
              style: context.text.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
                fontWeight: TypeTokens.semiBold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReceivableTile extends ConsumerWidget {
  const ReceivableTile({super.key, required this.item});
  final Receivable item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = item.project;
    final scheme = context.colors;
    final sub = [
      if ((p.service ?? '').isNotEmpty) p.service!,
      'Ödenen ${p.paid.format(hideZeroKurus: true)} / ${p.total.format(hideZeroKurus: true)}',
    ].join(' · ');
    return Semantics(
      button: true,
      label:
          '${p.displayLabel}, kalan ${p.remaining.format()}${item.isOverdue ? ', vadesi ${item.overdueDays} gün geçti' : ''}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () => showReceivableSheet(context, item),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.minTouch + 16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.displayLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall,
                      ),
                      Text(
                        sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (item.isOverdue)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: OverdueChip(days: item.overdueDays),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Kalan', style: context.text.bodySmall),
                    MoneyText(
                      p.remaining,
                      hideZeroKurus: true,
                      style: context.text.titleMedium?.copyWith(
                        color: item.isOverdue ? scheme.error : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showReceivableSheet(BuildContext context, Receivable item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ReceivableSheet(item: item),
  );
}

class _ReceivableSheet extends ConsumerStatefulWidget {
  const _ReceivableSheet({required this.item});
  final Receivable item;

  @override
  ConsumerState<_ReceivableSheet> createState() => _ReceivableSheetState();
}

class _ReceivableSheetState extends ConsumerState<_ReceivableSheet> {
  bool _busy = false;

  String _message() {
    final p = widget.item.project;
    return ReminderMessage.build(
      company: ref.read(brandProfileProvider).companyName,
      customer: p.customerName,
      remaining: p.remaining,
      projectCode: p.code,
    );
  }

  Future<void> _remind() async {
    final p = widget.item.project;
    final messenger = ScaffoldMessenger.of(context);
    final FinanceRepository repo = ref.read(financeRepositoryProvider);
    final launcher = ref.read(contactLauncherProvider);
    final text = _message();
    setState(() => _busy = true);
    String? phone = p.customerPhone;
    try {
      phone ??= await repo.customerPhone(p.customerName);
    } catch (_) {
      phone = null;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (phone == null || phone.trim().isEmpty) {
      showFinanceMessage(
        messenger,
        'Müşterinin telefon numarası bulunamadı. Müşteri kartına numara ekleyin.',
      );
      return;
    }
    final ok = await launcher.whatsapp(phone, text: text);
    if (!ok) {
      showFinanceMessage(messenger, 'WhatsApp açılamadı.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final p = item.project;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(p.displayLabel, style: context.text.titleLarge),
          if ((p.service ?? '').isNotEmpty)
            Text(p.service!, style: context.text.bodyMedium),
          const SizedBox(height: Space.lg),
          _Line('Sözleşme tutarı', p.total),
          _Line('Tahsil edilen', p.paid),
          _Line('Kalan', p.remaining, bold: true),
          if (p.endDate != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Vade: ${Fmt.date(p.endDate!)}',
                      style: context.text.bodyMedium,
                    ),
                  ),
                  if (item.isOverdue) OverdueChip(days: item.overdueDays),
                ],
              ),
            ),
          const SizedBox(height: Space.md),
          PaymentScheduleSection(project: p),
          const SizedBox(height: Space.lg),
          if ((p.customerPhone ?? '').isNotEmpty) ...[
            PhoneActions(
              phone: p.customerPhone,
              name: p.customerName,
              message: _message(),
            ),
            const SizedBox(height: Space.sm),
          ],
          FilledButton.icon(
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.pushNamed<bool>(
                FinanceRouteNames.addPayment,
                queryParameters: {'projectId': p.id},
              );
            },
            icon: const Icon(Icons.add_card),
            label: const Text('Ödeme ekle'),
          ),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : _remind,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chat),
            label: const Text("WhatsApp'ta hatırlat"),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.amount, {this.bold = false});
  final String label;
  final Money amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold ? context.text.titleMedium : context.text.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          MoneyText(amount, style: style),
        ],
      ),
    );
  }
}
