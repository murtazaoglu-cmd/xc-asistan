// Ödemeler sekmesi: seçili ayın tahsilatları. Dokun → düzenle; menü → sil (geri alınabilir).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/formatters.dart';
import '../../../core/util/money.dart';
import '../data/finance_calc.dart';
import '../data/finance_models.dart';
import '../data/finance_providers.dart';
import '../finance_nav.dart';
import 'finance_actions.dart';

IconData methodIcon(String method) {
  switch (method) {
    case 'Havale':
      return Icons.account_balance_outlined;
    case 'Nakit':
      return Icons.payments_outlined;
    case 'Kredi Kartı':
      return Icons.credit_card;
    default:
      return Icons.receipt_long_outlined;
  }
}

/// [range] içindeki ödemeler (yeniden eskiye); geri-al penceresindekiler gizli.
/// [method] ve [ownerId] verilirse yalnız onlar. [ownerId] boş metin: sahibi olmayanlar.
List<Payment> paymentsInRange(
  List<Payment> all,
  InstantRange range,
  Set<String> hidden, {
  String? method,
  String? ownerId,
}) {
  final list =
      all
          .where(
            (p) =>
                !hidden.contains(p.id) &&
                p.paidAt != null &&
                range.contains(p.paidAt!) &&
                (method == null || p.method == method) &&
                (ownerId == null ||
                    (ownerId.isEmpty
                        ? (p.ownerId ?? '').isEmpty
                        : p.ownerId == ownerId)),
          )
          .toList()
        ..sort((a, b) => b.paidAt!.compareTo(a.paidAt!));
  return list;
}

/// Seçili ayın ödemeleri (yeniden eskiye), geri-al penceresindekiler gizli.
List<Payment> paymentsOfMonth(
  List<Payment> all,
  YearMonth month,
  Set<String> hidden,
) => paymentsInRange(all, month.range, hidden);

class PaymentsTab extends ConsumerStatefulWidget {
  const PaymentsTab({super.key});

  @override
  ConsumerState<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends ConsumerState<PaymentsTab> {
  /// Yöntem süzgeci (null: tümü).
  String? _method;

  /// Sahip süzgeci (null: tümü; '' sahibi olmayanlar).
  String? _owner;

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(activePeriodProvider);
    final hidden = ref.watch(pendingDeletesProvider);
    final dir = ref.watch(ownerDirectoryProvider);
    final methods = ref.watch(paymentMethodOptionsProvider);
    return AsyncSection<List<Payment>>(
      value: ref.watch(paymentsProvider),
      onRetry: () => ref.invalidate(paymentsProvider),
      builder: (all) {
        final inPeriod = paymentsInRange(all, period.range, hidden);
        final items = paymentsInRange(
          all,
          period.range,
          hidden,
          method: _method,
          ownerId: _owner,
        );
        final allTime = Money.sum(
          all.where((p) => !hidden.contains(p.id)).map((p) => p.amount),
        );
        // Dönemdeki yöntemler: sağlayıcı seçenekleri + kayıtlarda görülen bilinmeyenler.
        final known = [for (final m in methods) m.api];
        final extra = {
          for (final p in inPeriod)
            if (p.method.isNotEmpty && !known.contains(p.method)) p.method,
        };
        final methodChips = [
          ...methods.map((m) => (m.api, m.label)),
          for (final e in extra) (e, e),
        ];
        final owners = FinanceCalc.byOwner(inPeriod);
        final hasFilter = _method != null || _owner != null;
        final children = <Widget>[
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              ChoiceChip(
                label: const Text('Tüm yöntemler'),
                selected: _method == null,
                onSelected: (_) => setState(() => _method = null),
              ),
              for (final m in methodChips)
                ChoiceChip(
                  label: Text(m.$2),
                  selected: _method == m.$1,
                  onSelected: (_) => setState(() => _method = m.$1),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          if (owners.length >= 2) ...[
            _OwnerSummary(
              owners: owners,
              dir: dir,
              selected: _owner,
              onSelect: (id) => setState(
                () => _owner = _owner == (id ?? '') ? null : (id ?? ''),
              ),
            ),
            const SizedBox(height: Space.md),
          ],
        ];
        if (items.isEmpty) {
          children.add(
            EmptyState(
              icon: Icons.payments_outlined,
              title: hasFilter
                  ? 'Bu süzgeçte ödeme yok'
                  : '${period.label} için ödeme yok',
              message: hasFilter
                  ? 'Süzgeci değiştirin ya da kaldırın.'
                  : 'Tahsilat kaydı eklediğinizde burada görünür.',
              actionLabel: hasFilter ? null : 'Ödeme ekle',
              onAction: hasFilter ? null : () => FinanceNav.addPayment(context),
            ),
          );
        } else {
          children
            ..add(
              _TotalHeader(
                label: '${items.length} ödeme',
                total: Money.sum(items.map((e) => e.amount)),
                key: const Key('payments-total'),
              ),
            )
            ..add(
              (ShellController.maybeOf(context)?.wide ?? false)
                  ? PaymentsTable(payments: items)
                  : Column(
                      children: [
                        for (final p in items) PaymentTile(payment: p),
                      ],
                    ),
            );
        }
        children
          ..add(const SizedBox(height: Space.sm))
          ..add(
            Row(
              key: const Key('payments-alltime'),
              children: [
                Expanded(
                  child: Text(
                    'Tüm zamanlar (tüm tahsilat)',
                    style: context.text.bodySmall,
                  ),
                ),
                MoneyText(allTime, style: context.text.titleSmall),
              ],
            ),
          );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }
}

/// "Kim ne kadar aldı": seçili dönemde tahsilatın kimin defterine yazıldığı. Satıra dokununca
/// liste o kişiye süzülür (yeniden dokunuş süzgeci kaldırır).
class _OwnerSummary extends StatelessWidget {
  const _OwnerSummary({
    required this.owners,
    required this.dir,
    required this.selected,
    required this.onSelect,
  });
  final List<OwnerTotal> owners;
  final OwnerDirectory dir;
  final String? selected;
  final void Function(String? ownerId) onSelect;

  @override
  Widget build(BuildContext context) => SectionCard(
    key: const Key('owner-summary'),
    title: 'Kim ne kadar aldı',
    padding: const EdgeInsets.symmetric(vertical: Space.sm),
    child: Column(
      children: [
        for (final o in owners)
          ListTile(
            minTileHeight: Sizes.minTouch,
            selected: selected == (o.ownerId ?? ''),
            leading: const Icon(Icons.person_outline),
            title: Text(dir.nameOf(o.ownerId)),
            subtitle: Text('${o.count} ödeme'),
            trailing: MoneyText(o.total, style: context.text.titleSmall),
            onTap: () => onSelect(o.ownerId),
          ),
      ],
    ),
  );
}

/// Geniş ekran (web) tablo görünümü: sıralanabilir sütunlar, CSV/yazdır. Satır = [PaymentTile] ile aynı eylem.
class PaymentsTable extends ConsumerWidget {
  const PaymentsTable({super.key, required this.payments});
  final List<Payment> payments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dir = ref.watch(ownerDirectoryProvider);
    return DataTableView<Payment>(
      key: const Key('payments-table'),
      items: payments,
      title: 'Ödemeler',
      fileName: 'odemeler',
      initialSort: 0,
      initialAscending: false,
      onRowTap: (p) => FinanceNav.editPayment(context, p),
      rowSemanticLabel: (p) => '${p.projectLabel}, ${p.amount.format()}',
      columns: [
        DataColumnSpec<Payment>(
          label: 'Tarih',
          width: 120,
          text: (p) => p.paidAt == null ? '' : Fmt.date(p.paidAt!),
          sortKey: (p) => p.paidAt,
        ),
        DataColumnSpec<Payment>(
          label: 'Proje / müşteri',
          flex: 3,
          text: (p) => p.projectLabel,
          sortKey: (p) => p.projectLabel,
        ),
        DataColumnSpec<Payment>(
          label: 'Yöntem',
          width: 130,
          text: (p) => p.methodLabel,
          sortKey: (p) => p.methodLabel,
        ),
        DataColumnSpec<Payment>(
          label: 'Defter',
          flex: 1,
          text: (p) => dir.otherOwnerName(p.ownerId) ?? '',
        ),
        DataColumnSpec<Payment>(
          label: 'Not',
          flex: 2,
          text: (p) => p.note ?? '',
        ),
        DataColumnSpec<Payment>(
          label: 'Tutar',
          width: 140,
          numeric: true,
          text: (p) => p.amount.format(),
          sortKey: (p) => p.amount.kurus,
          cell: (context, p) =>
              MoneyText(p.amount, style: context.text.titleSmall),
        ),
      ],
      trailingBuilder: (context, p) => PopupMenuButton<String>(
        tooltip: 'Ödeme işlemleri',
        onSelected: (v) {
          if (v == 'edit') FinanceNav.editPayment(context, p);
          if (v == 'delete') deletePaymentWithUndo(context, ref, p);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Düzenle')),
          PopupMenuItem(value: 'delete', child: Text('Sil')),
        ],
      ),
    );
  }
}

class PaymentTile extends ConsumerWidget {
  const PaymentTile({super.key, required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = payment;
    final scheme = context.colors;
    final other = ref.watch(ownerDirectoryProvider).otherOwnerName(p.ownerId);
    final sub = [
      if (p.paidAt != null) Fmt.date(p.paidAt!),
      p.methodLabel,
      if (other != null) 'Defter: $other',
      if ((p.note ?? '').isNotEmpty) p.note!,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: () => FinanceNav.editPayment(context, p),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.minTouch + 16),
          child: Padding(
            padding: const EdgeInsets.only(left: Space.md),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: context.xc.successContainer,
                  child: Icon(methodIcon(p.method), color: context.xc.success),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.projectLabel,
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
                    ],
                  ),
                ),
                MoneyText(p.amount, style: context.text.titleMedium),
                PopupMenuButton<String>(
                  tooltip: 'Ödeme işlemleri',
                  onSelected: (v) {
                    if (v == 'edit') FinanceNav.editPayment(context, p);
                    if (v == 'delete') deletePaymentWithUndo(context, ref, p);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                    PopupMenuItem(value: 'delete', child: Text('Sil')),
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

class _TotalHeader extends StatelessWidget {
  const _TotalHeader({super.key, required this.label, required this.total});
  final String label;
  final Money total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.sm),
    child: Row(
      children: [
        Expanded(child: Text(label, style: context.text.bodyMedium)),
        const Text('Toplam '),
        MoneyText(total, style: context.text.titleMedium),
      ],
    ),
  );
}

/// AsyncValue → iskelet / hata (Tekrar dene) / veri (sekme içi, kaydırma gövdesi dışı).
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Column(
        children: [
          SkeletonBox(height: 72, radius: Radii.card),
          SizedBox(height: Space.sm),
          SkeletonBox(height: 72, radius: Radii.card),
          SizedBox(height: Space.sm),
          SkeletonBox(height: 72, radius: Radii.card),
        ],
      ),
      error: (e, _) => SizedBox(
        height: 280,
        child: ErrorState(error: e, onRetry: onRetry),
      ),
      data: builder,
    );
  }
}
