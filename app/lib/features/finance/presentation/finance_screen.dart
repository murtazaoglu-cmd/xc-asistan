// Para sekmesi. ÜSTTE hızlı giriş butonları (Ödeme ekle / Gider ekle), sonra ay seçici ve
// sekmeler: Özet · Ödemeler · Giderler · Sabit giderler. saha rolü bu ekranı GÖRMEZ.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/util/dates.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/finance_providers.dart';
import '../finance_nav.dart';
import 'expenses_tab.dart';
import 'payments_tab.dart';
import 'recurring_tab.dart';
import 'summary_tab.dart';

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  int _length = 0;

  void _ensureTabs(int length) {
    if (_tabs != null && _length == length) return;
    _tabs?.dispose();
    _length = length;
    _tabs = TabController(length: length, vsync: this)
      ..addListener(() {
        if (!_tabs!.indexIsChanging && mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(paymentsProvider);
    ref.invalidate(expensesProvider);
    ref.invalidate(allProjectsProvider);
    ref.invalidate(recurringProvider);
    try {
      await Future.wait([
        ref.read(paymentsProvider.future),
        ref.read(expensesProvider.future),
      ]);
    } catch (_) {
      // Hata ilgili sekmede "Tekrar dene" ile gösterilir.
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(financeAccessProvider);
    final title = ref.watch(brandProfileProvider).terms.money;
    if (access == null || !access.canView) {
      return AppScaffold(
        title: title,
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm için yetkiniz yok',
          message: 'Para bilgilerini yalnızca yetkili kullanıcılar görebilir.',
        ),
      );
    }
    final showRecurring = access.canManageRecurring;
    final labels = <String>[
      'Özet',
      'Ödemeler',
      'Giderler',
      if (showRecurring) 'Sabit giderler',
    ];
    _ensureTabs(labels.length);
    final index = _tabs!.index;

    final Widget content = switch (index) {
      0 => SummaryTab(access: access),
      1 => const PaymentsTab(),
      2 => ExpensesTab(access: access),
      _ => const RecurringTab(),
    };

    final wide = ShellController.maybeOf(context)?.wide ?? false;
    return AppScaffold(
      title: title,
      wideLayout: true,
      actions: [
        IconButton(
          tooltip: 'Yenile',
          icon: const Icon(Icons.refresh),
          onPressed: _refresh,
        ),
      ],
      body: PullToRefresh(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                wide ? Space.xl : Space.lg,
                Space.lg,
                wide ? Space.xl : Space.lg,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, c) => wide && c.maxWidth >= 860
                      ? const Row(
                          children: [
                            SizedBox(width: 380, child: MonthSelector()),
                            Spacer(),
                            SizedBox(width: 420, child: QuickActions()),
                          ],
                        )
                      : const Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            QuickActions(),
                            SizedBox(height: Space.md),
                            MonthSelector(),
                          ],
                        ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final l in labels) Tab(text: l)],
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                wide ? Space.xl : Space.lg,
                Space.lg,
                wide ? Space.xl : Space.lg,
                Space.xxxl,
              ),
              sliver: SliverToBoxAdapter(child: content),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sayfanın ÜSTÜNDE: hızlı veri girişi (başparmak erişimi, ≥ 52 dp).
class QuickActions extends StatelessWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    const minSize = Size.fromHeight(52);
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const Key('quick-add-payment'),
            style: FilledButton.styleFrom(minimumSize: minSize),
            onPressed: () => FinanceNav.addPayment(context),
            icon: const Icon(Icons.add_card),
            label: const Text('Ödeme ekle'),
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: FilledButton.tonalIcon(
            key: const Key('quick-add-expense'),
            style: FilledButton.styleFrom(minimumSize: minSize),
            onPressed: () => FinanceNav.addExpense(context),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Gider ekle'),
          ),
        ),
      ],
    );
  }
}

/// Dönem seçici: önceki / sonraki ay (geleceğe gidilmez) ya da serbest tarih aralığı
/// (başlangıç + bitiş, bitiş günü dahil). Aralık seçiliyken ay okları yerine aralık çipi görünür.
class MonthSelector extends ConsumerWidget {
  const MonthSelector({super.key});

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final today = Ist.wall(Ist.now());
    final last = DateTime(today.year, today.month, today.day);
    final current = ref.read(activePeriodProvider);
    DateTimeRange? initial;
    if (current.isCustom) {
      final a = Ist.wall(current.startDay!);
      final b = Ist.wall(current.endDay!);
      initial = DateTimeRange(
        start: DateTime(a.year, a.month, a.day),
        end: DateTime(b.year, b.month, b.day),
      );
    }
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: last,
      initialDateRange: initial,
      helpText: 'Tarih aralığı seçin',
      saveText: 'Uygula',
      cancelText: 'Vazgeç',
    );
    if (picked == null) return;
    ref
        .read(customPeriodProvider.notifier)
        .setRange(
          Ist.fromWall(picked.start.year, picked.start.month, picked.start.day),
          Ist.fromWall(picked.end.year, picked.end.month, picked.end.day),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final custom = ref.watch(customPeriodProvider);
    final notifier = ref.read(selectedMonthProvider.notifier);
    const touch = BoxConstraints(
      minWidth: Sizes.minTouch,
      minHeight: Sizes.minTouch,
    );
    final rangeButton = IconButton(
      key: const Key('pick-range'),
      tooltip: 'Tarih aralığı seç',
      constraints: touch,
      icon: const Icon(Icons.date_range),
      onPressed: () => _pickRange(context, ref),
    );
    if (custom != null) {
      return Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                key: const Key('range-chip'),
                avatar: const Icon(Icons.date_range, size: Sizes.iconSm),
                label: Text(custom.label),
                deleteButtonTooltipMessage: 'Aralığı kaldır (aylara dön)',
                onDeleted: () =>
                    ref.read(customPeriodProvider.notifier).clear(),
                onPressed: () => _pickRange(context, ref),
              ),
            ),
          ),
          rangeButton,
        ],
      );
    }
    return Row(
      children: [
        IconButton(
          tooltip: 'Önceki ay',
          constraints: touch,
          icon: const Icon(Icons.chevron_left),
          onPressed: notifier.previous,
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              month.label,
              textAlign: TextAlign.center,
              style: context.text.titleMedium,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Sonraki ay',
          constraints: touch,
          icon: const Icon(Icons.chevron_right),
          onPressed: notifier.canGoNext ? notifier.next : null,
        ),
        rangeButton,
      ],
    );
  }
}
