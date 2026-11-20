// Müşteri kartı (tasarım ekran 10): kimlik + Ara/WhatsApp, iletişim, özet sayılar,
// ödeme durumu, notlar, teklifler, projeler, yazışma geçmişi (genişletme noktası).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/money.dart';
import '../customers_routes.dart';
import '../data/customer_models.dart';
import '../data/customers_repository.dart';
import 'conversation_section.dart';
import 'customer_actions.dart';

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.phoneKey});
  final String phoneKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final caps = ref.watch(capabilitiesProvider);
    if (caps == null || !caps.showCustomers) {
      return AppScaffold(
        title: terms.customer,
        showMenuButton: false,
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm için yetkiniz yok',
        ),
      );
    }
    final customer = ref.watch(customerProvider(phoneKey));
    Future<void> refresh() async {
      ref.invalidate(customerHistoryProvider(phoneKey));
      ref.invalidate(customerProvider(phoneKey));
      await ref.read(customerProvider(phoneKey).future);
    }

    final c = customer.value;
    return AppScaffold(
      title: c?.displayName ?? terms.customer,
      showMenuButton: false,
      actions: [
        if (c != null) ...[
          IconButton(
            tooltip: 'Düzenle',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final saved = await context.push<bool>(
                CustomerRoutes.edit(phoneKey),
              );
              if (saved == true) await refresh();
            },
          ),
          IconButton(
            tooltip: 'Sil',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => CustomerActions.deleteWithUndo(context, c),
          ),
        ],
      ],
      body: AsyncValueView<Customer>(
        value: customer,
        onRetry: () => ref.invalidate(customerProvider(phoneKey)),
        data: (c) => PullToRefresh(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Space.lg),
            children: [
              _Header(customer: c),
              const SizedBox(height: Space.md),
              _Stats(customer: c),
              const SizedBox(height: Space.md),
              _PaymentCard(customer: c),
              const SizedBox(height: Space.md),
              _NotesCard(customer: c, onSaved: refresh),
              const SizedBox(height: Space.md),
              _OffersCard(phoneKey: phoneKey),
              const SizedBox(height: Space.md),
              _ProjectsCard(phoneKey: phoneKey),
              const SizedBox(height: Space.md),
              ConversationSection(customer: c),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final c = customer;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: context.colors.primaryContainer,
                foregroundColor: context.colors.onPrimaryContainer,
                child: Text(c.initials, style: context.text.titleLarge),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.displayName, style: context.text.titleLarge),
                    if ((c.region ?? '').isNotEmpty)
                      Text(c.region!, style: context.text.bodyMedium),
                    const SizedBox(height: Space.xs),
                    StatusChip(
                      label: c.isOfferDerived
                          ? '${terms.offer} kaynaklı'
                          : 'Elle eklendi',
                      tone: c.isOfferDerived
                          ? StatusTone.info
                          : StatusTone.neutral,
                      icon: c.isOfferDerived
                          ? Icons.request_quote_outlined
                          : Icons.edit_note,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          PhoneActionButtons(phone: c.phone, name: c.name),
          const SizedBox(height: Space.sm),
          if ((c.phone ?? '').isNotEmpty)
            PhoneActions(phone: c.phone, name: c.name),
          if ((c.email ?? '').isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Sizes.minTouch),
              child: Row(
                children: [
                  Icon(
                    Icons.mail_outline,
                    size: Sizes.iconSm,
                    color: context.colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(c.email!, style: context.text.bodyLarge),
                  ),
                ],
              ),
            ),
          AddressActions(
            address: c.address,
            lat: c.lat,
            lng: c.lng,
            showButton: true,
          ),
        ],
      ),
    );
  }
}

class _Stats extends ConsumerWidget {
  const _Stats({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final c = customer;
    Widget tile(String label, String value, IconData icon) => Expanded(
      child: StatTile(label: label, value: value, icon: icon),
    );
    return Column(
      children: [
        Row(
          children: [
            tile(terms.offers, '${c.offerCount}', Icons.request_quote_outlined),
            const SizedBox(width: Space.md),
            tile(terms.jobs, '${c.projectCount}', Icons.work_outline),
          ],
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            tile(
              'Toplam sözleşme',
              c.totalContracted.format(hideZeroKurus: true),
              Icons.handshake_outlined,
            ),
            const SizedBox(width: Space.md),
            tile(
              'Toplam ödeme',
              c.totalPaid.format(hideZeroKurus: true),
              Icons.payments_outlined,
            ),
          ],
        ),
      ],
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final total = c.totalContracted.kurus;
    final ratio = total <= 0
        ? 0.0
        : (c.totalPaid.kurus / total).clamp(0.0, 1.0);
    Widget row(String label, Money m, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.text.bodyLarge)),
          MoneyText(
            m,
            style: strong ? context.text.titleMedium : context.text.bodyLarge,
          ),
        ],
      ),
    );
    return SectionCard(
      title: 'Ödeme durumu',
      child: Column(
        children: [
          row('Sözleşme', c.totalContracted),
          row('Ödenen', c.totalPaid),
          row('Kalan', c.remaining, strong: true),
          const SizedBox(height: Space.sm),
          Semantics(
            label: 'Tahsilat oranı yüzde ${(ratio * 100).round()}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(value: ratio, minHeight: 8),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                '%${(ratio * 100).round()} tahsil edildi',
                style: context.text.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesCard extends ConsumerWidget {
  const _NotesCard({required this.customer, required this.onSaved});
  final Customer customer;
  final Future<void> Function() onSaved;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: customer.note ?? '');
    final messenger = ScaffoldMessenger.of(context);
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          Space.lg,
          Space.lg,
          Space.lg,
          MediaQuery.viewInsetsOf(ctx).bottom + Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Not', style: ctx.text.titleMedium),
            const SizedBox(height: Space.md),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Örn. Cuma günü evde olacak, ölçü 3,2 m.',
              ),
            ),
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (text == null) return;
    try {
      await ref
          .read(customersRepositoryProvider)
          .update(
            customer.phoneKey,
            CustomerInput(
              name: customer.name,
              phone: customer.phone ?? '',
              email: customer.email ?? '',
              region: customer.region ?? '',
              address: customer.address ?? '',
              note: text,
            ),
          );
      await onSaved();
      messenger.showSnackBar(const SnackBar(content: Text('Not kaydedildi.')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AppException.from(e).message)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = (customer.note ?? '').trim();
    final history = ref.watch(customerHistoryProvider(customer.phoneKey));
    final offerNotes = (history.value?.offers ?? const <CustomerOffer>[])
        .where((o) => (o.notes ?? '').trim().isNotEmpty)
        .toList();
    return SectionCard(
      title: 'Notlar',
      trailing: customer.isOfferDerived
          ? null
          : TextButton.icon(
              onPressed: () => _edit(context, ref),
              icon: const Icon(Icons.edit_note),
              label: Text(note.isEmpty ? 'Not ekle' : 'Düzenle'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note.isNotEmpty)
            Text(note, style: context.text.bodyLarge)
          else if (offerNotes.isEmpty)
            Text(
              'Not yok.',
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          for (final o in offerNotes) ...[
            const SizedBox(height: Space.sm),
            Text('${o.code ?? ''}: ${o.notes}', style: context.text.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _OffersCard extends ConsumerWidget {
  const _OffersCard({required this.phoneKey});
  final String phoneKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final h = ref.watch(customerHistoryProvider(phoneKey));
    return SectionCard(
      title: terms.offers,
      child: _HistoryBody<CustomerOffer>(
        value: h.whenData((v) => v.offers),
        emptyText: 'Henüz ${terms.offer.toLowerCase()} yok.',
        onRetry: () => ref.invalidate(customerHistoryProvider(phoneKey)),
        itemBuilder: (o) => _HistoryRow(
          title: [o.code, o.service].whereType<String>().join(' · '),
          date: o.createdAt,
          chip: StatusChip.offer(o.status),
          amount: o.total,
          onTap: () => context.go(Routes.offer(o.id)),
        ),
      ),
    );
  }
}

class _ProjectsCard extends ConsumerWidget {
  const _ProjectsCard({required this.phoneKey});
  final String phoneKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final h = ref.watch(customerHistoryProvider(phoneKey));
    return SectionCard(
      title: terms.jobs,
      child: _HistoryBody<CustomerProject>(
        value: h.whenData((v) => v.projects),
        emptyText: 'Henüz ${terms.job.toLowerCase()} yok.',
        onRetry: () => ref.invalidate(customerHistoryProvider(phoneKey)),
        itemBuilder: (p) => _HistoryRow(
          title: [p.code, p.service].whereType<String>().join(' · '),
          date: p.startDate,
          chip: StatusChip.stage(p.stage),
          amount: p.total,
          subAmountLabel: 'Ödenen',
          subAmount: p.paid,
          onTap: () => context.go(Routes.project(p.id)),
        ),
      ),
    );
  }
}

class _HistoryBody<T> extends StatelessWidget {
  const _HistoryBody({
    required this.value,
    required this.emptyText,
    required this.itemBuilder,
    required this.onRetry,
  });
  final AsyncValue<List<T>> value;
  final String emptyText;
  final Widget Function(T) itemBuilder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Column(
        children: [
          SkeletonBox(height: 48),
          SizedBox(height: Space.sm),
          SkeletonBox(height: 48),
        ],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppException.from(e).message),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar dene'),
          ),
        ],
      ),
      data: (items) => items.isEmpty
          ? Text(
              emptyText,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            )
          : Column(children: [for (final i in items) itemBuilder(i)]),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.title,
    required this.chip,
    required this.onTap,
    this.date,
    this.amount,
    this.subAmount,
    this.subAmountLabel,
  });
  final String title;
  final Widget chip;
  final VoidCallback onTap;
  final DateTime? date;
  final Money? amount;
  final Money? subAmount;
  final String? subAmountLabel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.minTouch + 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? '-' : title,
                      style: context.text.titleSmall,
                    ),
                    DateText(date, style: context.text.bodySmall),
                    const SizedBox(height: Space.xs),
                    chip,
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (amount != null)
                    MoneyText(amount!, style: context.text.titleSmall),
                  if (subAmount != null)
                    Text.rich(
                      TextSpan(
                        text: '${subAmountLabel ?? ''} ',
                        style: context.text.bodySmall,
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: MoneyText(
                              subAmount!,
                              style: context.text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              Icon(Icons.chevron_right, color: context.colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
