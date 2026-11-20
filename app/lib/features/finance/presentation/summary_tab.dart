// Özet sekmesi: Gelir / Gider / Kâr kartları (+ Ev / Dükkan / İşletme gider satırları), aylık grafik, alacaklar.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/money.dart';
import '../data/finance_access.dart';
import '../data/finance_calc.dart';
import '../data/finance_models.dart';
import '../data/finance_providers.dart';
import 'finance_chart.dart';
import 'receivables_section.dart';

class SummaryTab extends ConsumerWidget {
  const SummaryTab({super.key, required this.access});
  final FinanceAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(activePeriodProvider);
    final payments = ref.watch(paymentsProvider);
    final expenses = ref.watch(expensesProvider);
    final loading = payments.isLoading || expenses.isLoading;
    final error = payments.error ?? expenses.error;

    if (error != null && !(payments.hasValue && expenses.hasValue)) {
      return Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 240),
            child: ErrorState(
              error: error,
              onRetry: () {
                ref.invalidate(paymentsProvider);
                ref.invalidate(expensesProvider);
              },
            ),
          ),
          const ReceivablesSection(),
        ],
      );
    }
    if (loading && !(payments.hasValue && expenses.hasValue)) {
      return const Column(
        children: [
          SkeletonBox(height: 88, radius: Radii.card),
          SizedBox(height: Space.md),
          SkeletonBox(height: 100, radius: Radii.card),
          SizedBox(height: Space.md),
          SkeletonBox(height: 240, radius: Radii.card),
        ],
      );
    }
    final pl = payments.value ?? const <Payment>[];
    final el = expenses.value ?? const <Expense>[];
    final totals = FinanceCalc.totalsForRange(pl, el, period.range);
    final breakdown = FinanceCalc.breakdownForRange(el, period.range);
    final window = FinanceCalc.chartWindow(pl, el, period.endMonth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Geniş ekranda özet kartları ile grafik yan yana; dar ekranda alt alta (eskisi gibi).
        SideBySide(
          gap: Space.lg,
          minChildWidth: 440,
          children: [
            MonthSummary(
              totals: totals,
              breakdown: breakdown,
              showPersonal: access.canUsePersonalScope,
              periodLabel: period.isCustom ? period.label : null,
            ),
            SectionCard(
              title: 'Son ${window.length} ay',
              child: FinanceChart(months: window),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        const ReceivablesSection(),
      ],
    );
  }
}

/// Gelir / Gider / Kâr(Zarar) kartları + Ev / Dükkan / İşletme gider kırılımı.
/// Ev giderleri kâra DAHİL DEĞİL. [periodLabel] serbest tarih aralığında başlık olarak görünür.
class MonthSummary extends StatelessWidget {
  const MonthSummary({
    super.key,
    required this.totals,
    this.breakdown,
    this.showPersonal = true,
    this.periodLabel,
  });
  final MonthTotals totals;

  /// Verilirse Dükkan / İşletme satırları da gösterilir.
  final ScopeBreakdown? breakdown;
  final bool showPersonal;
  final String? periodLabel;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    final scheme = context.colors;
    final profit = totals.profit;
    final margin = totals.marginPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (periodLabel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              'Seçili aralık: $periodLabel',
              key: const Key('period-heading'),
              style: context.text.titleSmall,
            ),
          ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _AmountCard(
                  key: const Key('card-revenue'),
                  label: 'Gelir',
                  icon: Icons.south_west,
                  color: x.success,
                  amount: totals.revenue,
                  caption: '${totals.paymentCount} tahsilat',
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: _AmountCard(
                  key: const Key('card-expense'),
                  label: 'Gider',
                  icon: Icons.north_east,
                  color: scheme.error,
                  amount: totals.businessExpense,
                  caption: 'İşletme giderleri',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        _AmountCard(
          key: const Key('card-profit'),
          label: profit.isNegative ? 'Zarar' : 'Kâr',
          icon: profit.isNegative ? Icons.trending_down : Icons.trending_up,
          color: profit.isNegative ? scheme.error : x.success,
          amount: profit,
          large: true,
          caption: margin == null
              ? 'Gelir − (dükkan + işletme gideri)'
              : 'Marj %$margin · Gelir − (dükkan + işletme gideri)',
        ),
        const SizedBox(height: Space.md),
        if (showPersonal)
          _ScopeRow(
            key: const Key('row-personal'),
            icon: Icons.home_outlined,
            title: ScopeView.personal.groupLabel,
            caption: 'İşletme kârına dahil değil',
            amount: totals.personalExpense,
          ),
        if (breakdown != null) ...[
          if (showPersonal) const SizedBox(height: Space.sm),
          _ScopeRow(
            key: const Key('row-shop'),
            icon: Icons.storefront_outlined,
            title: ScopeView.business.groupLabel,
            caption: 'Kâra dahil',
            amount: breakdown!.shop,
          ),
          const SizedBox(height: Space.sm),
          _ScopeRow(
            key: const Key('row-general'),
            icon: Icons.business_center_outlined,
            title: ScopeView.general.groupLabel,
            caption: 'Kâra dahil',
            amount: breakdown!.business,
          ),
        ],
      ],
    );
  }
}

class _ScopeRow extends StatelessWidget {
  const _ScopeRow({
    super.key,
    required this.icon,
    required this.title,
    required this.caption,
    required this.amount,
  });
  final IconData icon;
  final String title;
  final String caption;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                Text(caption, style: context.text.bodySmall),
              ],
            ),
          ),
          MoneyText(amount, style: context.text.titleMedium),
        ],
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.amount,
    required this.caption,
    this.large = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Money amount;
  final String caption;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Semantics(
      label: '$label: ${amount.format()}. $caption',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: Shadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: Sizes.iconSm),
                const SizedBox(width: Space.xs),
                Text(label, style: context.text.titleSmall),
              ],
            ),
            const SizedBox(height: Space.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyText(
                amount,
                style:
                    (large
                            ? context.text.headlineMedium
                            : context.text.titleLarge)
                        ?.copyWith(color: color, fontWeight: TypeTokens.bold),
              ),
            ),
            Text(
              caption,
              style: context.text.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
