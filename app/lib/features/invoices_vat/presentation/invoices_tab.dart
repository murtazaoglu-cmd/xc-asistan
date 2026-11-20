// Faturalar sekmesi: giden/gelen, durum çipleri, arama, dönem, liste.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/invoices_vat_models.dart';
import '../data/invoices_vat_providers.dart';
import 'inv_widgets.dart';

class InvoicesTab extends ConsumerStatefulWidget {
  const InvoicesTab({super.key});

  @override
  ConsumerState<InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends ConsumerState<InvoicesTab> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(invoiceFilterProvider.notifier).setQuery(v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(invoiceFilterProvider);
    final list = ref.watch(invoiceListProvider);
    final n = ref.read(invoiceFilterProvider.notifier);

    Future<void> refresh() async {
      ref.invalidate(invoiceListProvider);
      ref.invalidate(invoiceSummaryProvider);
      try {
        await ref.read(invoiceListProvider.future);
      } catch (_) {}
    }

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: _onSearch,
            decoration: InputDecoration(
              labelText: 'Ara (belge no, karşı taraf)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Aramayı temizle',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        n.setQuery('');
                        setState(() {});
                      },
                    ),
            ),
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            children: [
              ChoiceChip(
                label: const Text('Tümü'),
                selected: f.direction == null,
                onSelected: (_) => n.setDirection(null),
              ),
              for (final d in InvoiceDirection.values)
                ChoiceChip(
                  key: Key('dir_${d.api}'),
                  avatar: Icon(
                    d == InvoiceDirection.giden
                        ? Icons.north_east
                        : Icons.south_west,
                    size: Sizes.iconSm,
                  ),
                  label: Text(d.label),
                  selected: f.direction == d,
                  onSelected: (_) =>
                      n.setDirection(f.direction == d ? null : d),
                ),
            ],
          ),
          Wrap(
            spacing: Space.sm,
            children: [
              for (final s in InvoiceStatus.values)
                FilterChip(
                  key: Key('status_${s.api}'),
                  label: Text(s.label),
                  selected: f.statuses.contains(s),
                  onSelected: (_) => n.toggleStatus(s),
                ),
              FilterChip(
                key: const Key('status_overdue'),
                label: const Text('Vadesi geçen'),
                selected: f.overdueOnly,
                onSelected: n.setOverdue,
              ),
            ],
          ),
          PeriodBar(
            label: f.period == null ? 'Tüm dönemler' : f.period!.monthLabel,
            onPrevious: f.period == null
                ? null
                : () => n.setPeriod(f.period!.previousMonth),
            onNext: f.period == null
                ? null
                : () => n.setPeriod(f.period!.nextMonth),
            trailing: FilterChip(
              key: const Key('all_periods'),
              label: const Text('Tümü'),
              selected: f.period == null,
              onSelected: (s) => n.setPeriod(s ? null : PeriodSel.now()),
            ),
          ),
          if (f.period != null) _SummaryStrip(period: f.period!.monthKey),
        ],
      ),
    );

    return PullToRefresh(
      onRefresh: refresh,
      child: list.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            header,
            for (var i = 0; i < 4; i++)
              const Padding(
                padding: EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
                child: SkeletonBox(height: 84, radius: Radii.card),
              ),
          ],
        ),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            header,
            SizedBox(
              height: 320,
              child: ErrorState(
                error: e,
                onRetry: () => ref.invalidate(invoiceListProvider),
              ),
            ),
          ],
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                header,
                SizedBox(
                  height: 360,
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: f.isActive
                        ? 'Eşleşen fatura yok'
                        : 'Henüz fatura yok',
                    message: f.isActive ? 'Filtreleri değiştirmeyi deneyin.' : 'Kestiğiniz ve aldığınız faturaları buradan takip edin. Uygulama fatura kesmez.',
                    actionLabel: f.isActive
                        ? 'Filtreleri temizle'
                        : 'Fatura ekle',
                    onAction: f.isActive
                        ? () {
                            _search.clear();
                            n.clear();
                          }
                        : () => context.push('${Routes.invoicesVat}/new'),
                  ),
                ),
              ],
            );
          }
          if (ShellController.maybeOf(context)?.wide ?? false) {
            // Geniş ekran (web): tablo görünümü (sıralanabilir sütunlar, CSV, yazdır).
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                header,
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.md,
                    Space.lg,
                    0,
                  ),
                  child: InvoicesTable(invoices: page.items),
                ),
                if (page.hasMore(0))
                  Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: OutlinedButton(
                      onPressed: n.loadMore,
                      child: Text(
                        'Daha fazla yükle (${page.items.length}/${page.total})',
                      ),
                    ),
                  ),
              ],
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: page.items.length + 2,
            itemBuilder: (context, i) {
              if (i == 0) return header;
              if (i == page.items.length + 1) {
                return page.hasMore(0)
                    ? Padding(
                        padding: const EdgeInsets.all(Space.lg),
                        child: OutlinedButton(
                          onPressed: n.loadMore,
                          child: Text(
                            'Daha fazla yükle (${page.items.length}/${page.total})',
                          ),
                        ),
                      )
                    : const SizedBox.shrink();
              }
              return InvoiceCard(invoice: page.items[i - 1]);
            },
          );
        },
      ),
    );
  }
}

class _SummaryStrip extends ConsumerWidget {
  const _SummaryStrip({required this.period});
  final String period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(invoiceSummaryProvider(period));
    return s.maybeWhen(
      data: (v) => Padding(
        padding: const EdgeInsets.only(top: Space.xs),
        child: Row(
          children: [
            Expanded(
              child: MetricBox(
                label: 'Giden KDV',
                value: v.gidenKdv.format(),
                hint: 'Satışlardan',
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: MetricBox(
                label: 'Gelen KDV',
                value: v.gelenKdv.format(),
                hint: 'Alımlardan',
              ),
            ),
          ],
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Geniş ekran (web) tablo görünümü; satıra tıklama [InvoiceCard] ile aynı ayrıntı sayfasını açar.
class InvoicesTable extends StatelessWidget {
  const InvoicesTable({super.key, required this.invoices});
  final List<Invoice> invoices;

  @override
  Widget build(BuildContext context) => DataTableView<Invoice>(
    key: const Key('invoices-table'),
    items: invoices,
    title: 'Faturalar',
    fileName: 'faturalar',
    initialSort: 0,
    initialAscending: false,
    onRowTap: (i) => context.push('${Routes.invoicesVat}/${i.id}'),
    rowSemanticLabel: (i) => '${i.title}, ${i.tutar.format()}',
    columns: [
      DataColumnSpec<Invoice>(
        label: 'Tarih',
        width: 112,
        text: (i) => DateText.format(i.issueDate, DateTextMode.date),
        sortKey: (i) => i.issueDate,
      ),
      DataColumnSpec<Invoice>(
        label: 'Belge',
        flex: 3,
        text: (i) => i.title,
        sortKey: (i) => i.title,
      ),
      DataColumnSpec<Invoice>(
        label: 'Yön',
        width: 84,
        text: (i) => i.direction?.label ?? '',
        sortKey: (i) => i.direction?.label,
      ),
      DataColumnSpec<Invoice>(label: 'Tür', flex: 1, text: (i) => i.typeLabel),
      DataColumnSpec<Invoice>(
        label: 'Durum',
        width: 150,
        text: (i) =>
            '${i.status?.label ?? i.statusRaw}${i.overdue ? ' (vadesi geçti)' : ''}',
        sortKey: (i) => i.status?.label ?? i.statusRaw,
        cell: (context, i) => Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            invoiceStatusChip(i),
            if (i.overdue)
              const StatusChip(
                label: 'Vadesi geçti',
                tone: StatusTone.danger,
                icon: Icons.warning_amber,
              ),
          ],
        ),
      ),
      DataColumnSpec<Invoice>(
        label: 'Vade',
        width: 112,
        text: (i) => DateText.format(i.dueDate, DateTextMode.date),
        sortKey: (i) => i.dueDate,
      ),
      DataColumnSpec<Invoice>(
        label: 'Matrah',
        width: 120,
        numeric: true,
        text: (i) => i.matrah.format(),
        sortKey: (i) => i.matrah.kurus,
      ),
      DataColumnSpec<Invoice>(
        label: 'KDV',
        width: 110,
        numeric: true,
        text: (i) => i.kdv.format(),
        sortKey: (i) => i.kdv.kurus,
      ),
      DataColumnSpec<Invoice>(
        label: 'Tutar',
        width: 130,
        numeric: true,
        text: (i) => i.tutar.format(),
        sortKey: (i) => i.tutar.kurus,
        cell: (context, i) =>
            MoneyText(i.tutar, style: context.text.titleSmall),
      ),
    ],
  );
}

/// Liste kartı (dokunma ≥ 48 dp; tüm kart dokunulur).
class InvoiceCard extends StatelessWidget {
  const InvoiceCard({super.key, required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    final giden = i.direction == InvoiceDirection.giden;
    final meta = [
      if (i.issueDate != null) DateText.format(i.issueDate, DateTextMode.date),
      i.typeLabel,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
      child: Semantics(
        button: true,
        label:
            '${giden ? 'Giden' : 'Gelen'} fatura, ${i.title}, ${i.tutar.format()}, ${i.status?.label ?? i.statusRaw}',
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('invoice_${i.id}'),
            onTap: () => context.push('${Routes.invoicesVat}/${i.id}'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Sizes.minTouch + 24),
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: giden
                          ? context.xc.successContainer
                          : context.xc.infoContainer,
                      child: Icon(
                        giden ? Icons.north_east : Icons.south_west,
                        color: giden ? context.xc.success : context.xc.info,
                        semanticLabel: giden ? 'Giden' : 'Gelen',
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            i.title,
                            style: context.text.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            meta,
                            style: context.text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: Space.sm),
                          Wrap(
                            spacing: Space.sm,
                            runSpacing: Space.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              invoiceStatusChip(i),
                              if (i.overdue)
                                const StatusChip(
                                  label: 'Vadesi geçti',
                                  tone: StatusTone.danger,
                                  icon: Icons.warning_amber,
                                ),
                              if (i.confirmation.needed)
                                const StatusChip(
                                  label: 'Teyit edin',
                                  tone: StatusTone.warning,
                                  icon: Icons.fact_check_outlined,
                                ),
                              if (i.files.isNotEmpty)
                                Icon(
                                  Icons.attach_file,
                                  size: Sizes.iconSm,
                                  semanticLabel: '${i.files.length} ek',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        MoneyText(i.tutar, style: context.text.titleSmall),
                        if (!i.kdv.isZero)
                          Text(
                            'KDV ${i.kdv.format(hideZeroKurus: true)}',
                            style: context.text.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
