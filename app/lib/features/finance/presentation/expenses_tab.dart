// Giderler sekmesi: seçili ayın giderleri; kapsam süzgeci; Ev / Dükkan / İşletme ayrı toplam.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/formatters.dart';
import '../../../core/util/money.dart';
import '../data/finance_access.dart';
import '../data/finance_calc.dart';
import '../data/finance_input.dart';
import '../data/finance_models.dart';
import '../data/finance_providers.dart';
import '../finance_nav.dart';
import 'finance_actions.dart';
import 'payments_tab.dart' show AsyncSection;

enum ExpenseFilter {
  all('Tümü'),
  home('Ev'),
  shop('Dükkan'),
  business('İşletme');

  const ExpenseFilter(this.label);
  final String label;

  bool matches(Expense e) => switch (this) {
    ExpenseFilter.all => true,
    ExpenseFilter.home => e.scope == ScopeView.personal,
    ExpenseFilter.shop => e.scope == ScopeView.business,
    ExpenseFilter.business => e.scope == ScopeView.general,
  };
}

/// [range] içindeki giderler (yeniden eskiye).
List<Expense> expensesInRange(
  List<Expense> all,
  InstantRange range,
  Set<String> hidden, {
  ExpenseFilter filter = ExpenseFilter.all,
  bool allowPersonal = true,
}) {
  final list =
      all
          .where(
            (e) =>
                !hidden.contains(e.id) &&
                e.date != null &&
                range.contains(e.date!) &&
                (allowPersonal || !e.isPersonal) &&
                filter.matches(e),
          )
          .toList()
        ..sort((a, b) => b.date!.compareTo(a.date!));
  return list;
}

List<Expense> expensesOfMonth(
  List<Expense> all,
  YearMonth month,
  Set<String> hidden, {
  ExpenseFilter filter = ExpenseFilter.all,
  bool allowPersonal = true,
}) => expensesInRange(
  all,
  month.range,
  hidden,
  filter: filter,
  allowPersonal: allowPersonal,
);

class ExpensesTab extends ConsumerStatefulWidget {
  const ExpensesTab({super.key, required this.access});
  final FinanceAccess access;

  @override
  ConsumerState<ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends ConsumerState<ExpensesTab> {
  ExpenseFilter _filter = ExpenseFilter.all;

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(activePeriodProvider);
    final hidden = ref.watch(pendingDeletesProvider);
    final personalOk = widget.access.canUsePersonalScope;
    final filters = [
      for (final f in ExpenseFilter.values)
        if (f != ExpenseFilter.home || personalOk) f,
    ];
    return AsyncSection<List<Expense>>(
      value: ref.watch(expensesProvider),
      onRetry: () => ref.invalidate(expensesProvider),
      builder: (all) {
        final periodAll = expensesInRange(
          all,
          period.range,
          hidden,
          allowPersonal: personalOk,
        );
        final items = expensesInRange(
          all,
          period.range,
          hidden,
          filter: _filter,
          allowPersonal: personalOk,
        );
        final b = FinanceCalc.breakdownForRange(periodAll, period.range);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final f in filters)
                  ChoiceChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
            const SizedBox(height: Space.md),
            Container(
              key: const Key('expenses-totals'),
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Column(
                children: [
                  if (personalOk)
                    _TotalLine(
                      '${ScopeView.personal.groupLabel} (kâra dahil değil)',
                      b.home,
                    ),
                  _TotalLine(ScopeView.business.groupLabel, b.shop),
                  _TotalLine(ScopeView.general.groupLabel, b.business),
                ],
              ),
            ),
            const SizedBox(height: Space.md),
            if (items.isEmpty)
              EmptyState(
                icon: Icons.receipt_long_outlined,
                title: _filter == ExpenseFilter.all
                    ? '${period.label} için gider yok'
                    : 'Bu süzgeçte gider yok',
                message: 'Gider eklediğinizde burada görünür.',
                actionLabel: 'Gider ekle',
                onAction: () => FinanceNav.addExpense(context),
              )
            else if (ShellController.maybeOf(context)?.wide ?? false)
              ExpensesTable(expenses: items)
            else
              for (final e in items) ExpenseTile(expense: e),
          ],
        );
      },
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine(this.label, this.amount);
  final String label;
  final Money amount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: context.text.bodyMedium)),
        MoneyText(amount, style: context.text.titleSmall),
      ],
    ),
  );
}

/// Geniş ekran (web) tablo görünümü: [ExpenseTile] ile aynı eylemler.
class ExpensesTable extends ConsumerWidget {
  const ExpensesTable({super.key, required this.expenses});
  final List<Expense> expenses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final dir = ref.watch(ownerDirectoryProvider);
    return DataTableView<Expense>(
      key: const Key('expenses-table'),
      items: expenses,
      title: 'Giderler',
      fileName: 'giderler',
      initialSort: 0,
      initialAscending: false,
      onRowTap: (e) => FinanceNav.editExpense(context, e),
      rowSemanticLabel: (e) =>
          '${FinanceCategories.label(terms, e.category)}, ${e.amount.format()}',
      columns: [
        DataColumnSpec<Expense>(
          label: 'Tarih',
          width: 120,
          text: (e) => e.date == null ? '' : Fmt.date(e.date!),
          sortKey: (e) => e.date,
        ),
        DataColumnSpec<Expense>(
          label: 'Kategori',
          flex: 2,
          text: (e) => FinanceCategories.label(terms, e.category),
          sortKey: (e) => FinanceCategories.label(terms, e.category),
        ),
        DataColumnSpec<Expense>(
          label: 'Kapsam',
          width: 120,
          text: (e) => e.scope.label,
          sortKey: (e) => e.scope.label,
        ),
        DataColumnSpec<Expense>(
          label: 'Proje',
          flex: 2,
          text: (e) => e.hasProject ? e.projectLabel : '',
        ),
        DataColumnSpec<Expense>(
          label: 'Defter',
          flex: 1,
          text: (e) => dir.otherOwnerName(e.ownerId) ?? '',
        ),
        DataColumnSpec<Expense>(
          label: 'Not',
          flex: 2,
          text: (e) => e.note ?? '',
        ),
        DataColumnSpec<Expense>(
          label: 'Tutar',
          width: 140,
          numeric: true,
          text: (e) => e.amount.format(),
          sortKey: (e) => e.amount.kurus,
          cell: (context, e) =>
              MoneyText(e.amount, style: context.text.titleSmall),
        ),
      ],
      trailingBuilder: (context, e) => PopupMenuButton<String>(
        tooltip: 'Gider işlemleri',
        onSelected: (v) {
          if (v == 'edit') FinanceNav.editExpense(context, e);
          if (v == 'delete') deleteExpenseWithUndo(context, ref, e);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Düzenle')),
          PopupMenuItem(value: 'delete', child: Text('Sil')),
        ],
      ),
    );
  }
}

class ExpenseTile extends ConsumerWidget {
  const ExpenseTile({super.key, required this.expense});
  final Expense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = expense;
    final terms = ref.watch(brandProfileProvider).terms;
    final scheme = context.colors;
    final other = ref.watch(ownerDirectoryProvider).otherOwnerName(e.ownerId);
    final sub = [
      if (e.date != null) Fmt.date(e.date!),
      e.scope.label,
      if (other != null) 'Defter: $other',
      if (e.hasProject) e.projectLabel,
      if ((e.note ?? '').isNotEmpty) e.note!,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: () => FinanceNav.editExpense(context, e),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.minTouch + 16),
          child: Padding(
            padding: const EdgeInsets.only(left: Space.md),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: e.isPersonal
                      ? scheme.surfaceContainerHigh
                      : scheme.errorContainer,
                  child: Icon(
                    e.isPersonal
                        ? Icons.home_outlined
                        : Icons.receipt_long_outlined,
                    color: e.isPersonal
                        ? scheme.onSurfaceVariant
                        : scheme.onErrorContainer,
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        FinanceCategories.label(terms, e.category),
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
                MoneyText(e.amount, style: context.text.titleMedium),
                PopupMenuButton<String>(
                  tooltip: 'Gider işlemleri',
                  onSelected: (v) {
                    if (v == 'edit') FinanceNav.editExpense(context, e);
                    if (v == 'delete') deleteExpenseWithUndo(context, ref, e);
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
