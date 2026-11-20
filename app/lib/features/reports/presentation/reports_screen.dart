// Raporlar: genel durum (gelir-gider-kâr), para grafiği, tahsilat, proje kârlılığı, hizmet dağılımı.
// Kâr kuralı: ev (kişisel) giderler işletme kârına dahil DEĞİLDİR; ayrı satırda gösterilir.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/money.dart';
import '../data/report_charts.dart';
import '../data/report_models.dart';
import '../data/reports_repository.dart';
import 'money_chart.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider);
    if (caps == null || !caps.showReports) {
      return const AppScaffold(
        title: 'Raporlar',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm için yetkiniz yok',
        ),
      );
    }
    final range = ref.watch(reportRangeProvider);
    Future<void> refresh() async {
      ref.invalidate(reportSummaryProvider);
      ref.invalidate(reportProfitProvider(range));
      ref.invalidate(reportServiceProvider);
      ref.invalidate(projectProfitProvider);
      await Future.wait([
        ref.read(reportSummaryProvider.future).then((_) {}, onError: (_) {}),
        ref
            .read(reportProfitProvider(range).future)
            .then((_) {}, onError: (_) {}),
      ]);
    }

    final wide = ShellController.maybeOf(context)?.wide ?? false;
    return AppScaffold(
      title: 'Raporlar',
      wideLayout: true,
      body: PullToRefresh(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(wide ? Space.xl : Space.lg),
          // GENİŞ EKRAN: özet üstte tam genişlik, grafikler/tablolar yan yana (2 sütun).
          children: wide
              ? const [
                  ResponsiveColumns(
                    gap: Space.lg,
                    maxColumns: 2,
                    fullWidth: [_SummarySection()],
                    children: [
                      _ChartSection(),
                      _CollectionSection(),
                      _ProjectProfitSection(),
                      _ServiceSection(),
                    ],
                  ),
                ]
              : const [
                  _SummarySection(),
                  SizedBox(height: Space.md),
                  _ChartSection(),
                  SizedBox(height: Space.md),
                  _CollectionSection(),
                  SizedBox(height: Space.md),
                  _ProjectProfitSection(),
                  SizedBox(height: Space.md),
                  _ServiceSection(),
                ],
        ),
      ),
    );
  }
}

/// Bölüm içi yükleniyor / hata / veri (tüm ekranı kilitlemez).
class _Async<T> extends StatelessWidget {
  const _Async({required this.value, required this.data, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Column(
      children: [
        SkeletonBox(height: 56),
        SizedBox(height: Space.sm),
        SkeletonBox(height: 56),
      ],
    ),
    error: (e, _) => Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppException.from(e).isNetwork
                    ? Icons.wifi_off
                    : Icons.error_outline,
                color: context.colors.error,
              ),
              const SizedBox(width: Space.sm),
              Expanded(child: Text(AppException.from(e).message)),
            ],
          ),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar dene'),
            ),
        ],
      ),
    ),
    data: data,
  );
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow(
    this.label,
    this.amount, {
    this.strong = false,
    this.colorize = false,
    this.muted = false,
    this.icon,
  });
  final String label;
  final Money amount;
  final bool strong;
  final bool colorize;
  final bool muted;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final base = strong ? context.text.titleMedium : context.text.bodyLarge;
    final style = muted
        ? base?.copyWith(color: context.colors.onSurfaceVariant)
        : base;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: Sizes.iconSm,
              color: context.colors.onSurfaceVariant,
            ),
            const SizedBox(width: Space.sm),
          ],
          Expanded(child: Text(label, style: style)),
          MoneyText(amount, style: style, colorizeNegative: colorize),
        ],
      ),
    );
  }
}

// ---- 1. Genel durum ----

class _SummarySection extends ConsumerWidget {
  const _SummarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final s = ref.watch(reportSummaryProvider);
    return SectionCard(
      title: 'Genel durum',
      trailing: Text('Tüm zamanlar', style: context.text.bodySmall),
      child: _Async<ReportSummary>(
        value: s,
        onRetry: () => ref.invalidate(reportSummaryProvider),
        data: (r) {
          final x = context.xc;
          final loss = r.netProfit.isNegative;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              () {
                final revenue = StatTile(
                  label: 'Gelir',
                  value: r.totalRevenue.format(hideZeroKurus: true),
                  icon: Icons.south_west,
                );
                final expense = StatTile(
                  label: 'Gider',
                  value: r.businessExpenses.format(hideZeroKurus: true),
                  icon: Icons.north_east,
                  color: x.warning,
                );
                final net = StatTile(
                  label: loss ? 'Net zarar (işletme)' : 'Net kâr (işletme)',
                  value: r.netProfit.format(hideZeroKurus: true),
                  icon: loss ? Icons.trending_down : Icons.trending_up,
                  color: loss ? context.colors.error : x.success,
                );
                // Geniş ekran: üç kutu tek satırda eşit genişlikte.
                if (ShellController.maybeOf(context)?.wide ?? false) {
                  return Row(
                    children: [
                      Expanded(child: revenue),
                      const SizedBox(width: Space.md),
                      Expanded(child: expense),
                      const SizedBox(width: Space.md),
                      Expanded(child: net),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: revenue),
                        const SizedBox(width: Space.md),
                        Expanded(child: expense),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    net,
                  ],
                );
              }(),
              const SizedBox(height: Space.md),
              Text(
                'Net kâr = gelir − işletme gideri.',
                style: context.text.bodySmall,
              ),
              const Divider(height: Space.xl),
              // Ev giderleri işletme kârına DAHİL DEĞİL: ayrı satırlar.
              _MoneyRow(
                'Ev giderleri (kâra dahil değil)',
                r.homeExpenses,
                icon: Icons.home_outlined,
              ),
              _MoneyRow(
                'Ev giderleri dahil net',
                r.netProfitInclHome,
                muted: true,
                colorize: true,
              ),
              const Divider(height: Space.xl),
              Wrap(
                spacing: Space.xl,
                runSpacing: Space.sm,
                children: [
                  _Fact(terms.offers, '${r.totalOffers}'),
                  _Fact('Kabul oranı', '%${_pct(r.conversionRate)}'),
                  _Fact(
                    'Aktif ${terms.jobs.toLowerCase()}',
                    '${r.activeProjects}',
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

String _pct(double v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toStringAsFixed(1).replaceAll('.', ',');

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: context.text.titleLarge),
      Text(label, style: context.text.bodySmall),
    ],
  );
}

// ---- 2. Para grafiği ----

class _ChartSection extends ConsumerWidget {
  const _ChartSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    final profit = ref.watch(reportProfitProvider(range));
    return SectionCard(
      title: 'Gelir ve gider',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ReportRange>(
              showSelectedIcon: false,
              segments: [
                for (final r in ReportRange.values)
                  ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {range},
              onSelectionChanged: (s) =>
                  ref.read(reportRangeProvider.notifier).set(s.first),
            ),
          ),
          const SizedBox(height: Space.lg),
          _Async<List<ProfitPoint>>(
            value: profit,
            onRetry: () => ref.invalidate(reportProfitProvider(range)),
            data: (points) {
              final now = Ist.now();
              final data = range == ReportRange.monthly
                  ? MoneyChartData.monthly(points, now: now)
                  : MoneyChartData.yearly(points, now: now);
              if (!data.hasAnyData) {
                return const EmptyState(
                  icon: Icons.bar_chart,
                  title: 'Henüz gelir ya da gider kaydı yok',
                  message: 'Ödeme ve gider girildikçe grafik burada görünür.',
                );
              }
              return MoneyBarChart(key: ValueKey(range), data: data);
            },
          ),
        ],
      ),
    );
  }
}

// ---- 3. Tahsilat ----

class _CollectionSection extends ConsumerWidget {
  const _CollectionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final p = ref.watch(projectProfitProvider);
    return SectionCard(
      title: 'Tahsilat',
      child: _Async<List<ProjectProfit>>(
        value: p,
        onRetry: () => ref.invalidate(projectProfitProvider),
        data: (list) {
          final contract = Money.sum(list.map((e) => e.contract));
          final collected = Money.sum(list.map((e) => e.collected));
          final open = Money.sum(list.map((e) => e.outstanding));
          final ratio = contract.kurus <= 0
              ? 0.0
              : (collected.kurus / contract.kurus).clamp(0.0, 1.0);
          final debtors = list.where((e) => e.outstanding.isPositive).toList()
            ..sort((a, b) => b.outstanding.compareTo(a.outstanding));
          if (list.isEmpty) {
            return Text('Henüz ${terms.job.toLowerCase()} yok.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MoneyRow('Sözleşme toplamı', contract),
              _MoneyRow('Tahsil edilen', collected),
              _MoneyRow('Kalan alacak', open, strong: true),
              const SizedBox(height: Space.sm),
              Semantics(
                label: 'Tahsilat oranı yüzde ${(ratio * 100).round()}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(value: ratio, minHeight: 8),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  '%${(ratio * 100).round()} tahsil edildi',
                  style: context.text.bodySmall,
                ),
              ),
              if (debtors.isNotEmpty) ...[
                const SizedBox(height: Space.lg),
                Text('Açık bakiyesi en yüksek', style: context.text.titleSmall),
                for (final d in debtors.take(5))
                  _ProjectTile(
                    p: d,
                    trailing: MoneyText(
                      d.outstanding,
                      style: context.text.titleSmall,
                    ),
                    caption: 'Kalan',
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.p, required this.trailing, this.caption});
  final ProjectProfit p;
  final Widget trailing;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(Routes.project(p.id)),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.minTouch + 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyLarge,
                    ),
                    Text(
                      [p.code, p.service]
                          .whereType<String>()
                          .where((e) => e.isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (caption != null)
                    Text(caption!, style: context.text.bodySmall),
                  trailing,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- 4. Proje kârlılığı ----

class _ProjectProfitSection extends ConsumerStatefulWidget {
  const _ProjectProfitSection();

  @override
  ConsumerState<_ProjectProfitSection> createState() =>
      _ProjectProfitSectionState();
}

class _ProjectProfitSectionState extends ConsumerState<_ProjectProfitSection> {
  bool _all = false;
  static const int _top = 6;

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(brandProfileProvider).terms;
    final p = ref.watch(projectProfitProvider);
    return SectionCard(
      title: '${terms.job} kârlılığı',
      child: _Async<List<ProjectProfit>>(
        value: p,
        onRetry: () => ref.invalidate(projectProfitProvider),
        data: (list) {
          final rows =
              list
                  .where((e) => !e.collected.isZero || !e.expenses.isZero)
                  .toList()
                ..sort((a, b) => b.profit.compareTo(a.profit));
          if (rows.isEmpty) {
            return Text(
              'Henüz tahsilat ya da gider girilmiş ${terms.job.toLowerCase()} yok.',
            );
          }
          final shown = _all ? rows : rows.take(_top).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kâr = tahsilat − ${terms.job.toLowerCase()} giderleri.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: Space.sm),
              for (final e in shown)
                _ProjectTile(
                  p: e,
                  caption: e.marginPercent == null
                      ? null
                      : 'Marj %${_pct(e.marginPercent!.roundToDouble())}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        e.profit.isNegative
                            ? Icons.trending_down
                            : Icons.trending_up,
                        size: 18,
                        color: e.profit.isNegative
                            ? context.colors.error
                            : context.xc.success,
                      ),
                      const SizedBox(width: Space.xs),
                      MoneyText(
                        e.profit,
                        colorizeNegative: true,
                        style: context.text.titleSmall,
                      ),
                    ],
                  ),
                ),
              if (rows.length > _top)
                TextButton(
                  onPressed: () => setState(() => _all = !_all),
                  child: Text(
                    _all ? 'Daha az göster' : 'Tümünü göster (${rows.length})',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---- 5. Hizmet dağılımı (halka yerine sıralı yatay çubuk liste) ----

class _ServiceSection extends ConsumerWidget {
  const _ServiceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final s = ref.watch(reportServiceProvider);
    return SectionCard(
      title: 'Hizmet dağılımı',
      child: _Async<List<ServiceShare>>(
        value: s,
        onRetry: () => ref.invalidate(reportServiceProvider),
        data: (list) {
          if (list.isEmpty) {
            return Text('Henüz ${terms.offer.toLowerCase()} yok.');
          }
          final rows = ServiceShare.withPercent(list);
          final maxCount = rows.first.item.count == 0
              ? 1
              : rows.first.item.count;
          return Column(
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Semantics(
                    label:
                        '${r.item.service}: ${r.item.count} adet, yüzde ${_pct(r.percent.roundToDouble())}',
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.item.service,
                                style: context.text.bodyLarge,
                              ),
                            ),
                            Text(
                              '${r.item.count} · %${_pct(r.percent.roundToDouble())}',
                              style: context.text.bodyMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.xs),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.pill),
                          child: LinearProgressIndicator(
                            value: r.item.count / maxCount,
                            minHeight: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
