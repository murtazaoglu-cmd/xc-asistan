// Ödeme Planı sekmesi: yaşlandırma kartı + proje başına taksit/vade/çek-senet listesi.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/money.dart';
import '../data/invoices_vat_models.dart';
import '../data/invoices_vat_providers.dart';
import 'schedule_widgets.dart';

enum PlanFilter { all, pending, overdue, paid }

class PaymentPlanTab extends ConsumerStatefulWidget {
  const PaymentPlanTab({super.key});

  @override
  ConsumerState<PaymentPlanTab> createState() => _PaymentPlanTabState();
}

class _PaymentPlanTabState extends ConsumerState<PaymentPlanTab> {
  PlanFilter _filter = PlanFilter.pending;

  static const _labels = {
    PlanFilter.all: 'Tümü',
    PlanFilter.pending: 'Bekleyen',
    PlanFilter.overdue: 'Gecikmiş',
    PlanFilter.paid: 'Ödenen',
  };

  List<ScheduleItem> _apply(List<ScheduleItem> all) {
    final out = all.where((s) {
      switch (_filter) {
        case PlanFilter.all:
          return !s.isCancelled;
        case PlanFilter.pending:
          return s.isPending;
        case PlanFilter.overdue:
          return s.isOverdue();
        case PlanFilter.paid:
          return s.isPaid;
      }
    }).toList();
    out.sort((a, b) {
      final x = a.dueDate, y = b.dueDate;
      if (x == null || y == null) return x == null ? 1 : -1;
      return x.compareTo(y);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(scheduleProvider(const ScheduleFilter()));

    Future<void> refresh() async {
      ref.invalidate(scheduleProvider);
      ref.invalidate(agingProvider);
      try {
        await ref.read(scheduleProvider(const ScheduleFilter()).future);
      } catch (_) {}
    }

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AgingCard(),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            children: [
              for (final f in PlanFilter.values)
                ChoiceChip(
                  key: Key('plan_${f.name}'),
                  label: Text(_labels[f]!),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
        ],
      ),
    );

    return PullToRefresh(
      onRefresh: refresh,
      child: async.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            header,
            for (var i = 0; i < 3; i++)
              const Padding(
                padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
                child: SkeletonBox(height: 84, radius: Radii.md),
              ),
          ],
        ),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            header,
            SizedBox(
              height: 300,
              child: ErrorState(
                error: e,
                onRetry: () => ref.invalidate(scheduleProvider),
              ),
            ),
          ],
        ),
        data: (all) {
          final rows = _apply(all);
          if (rows.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                header,
                SizedBox(
                  height: 320,
                  child: EmptyState(
                    icon: Icons.event_repeat_outlined,
                    title: all.isEmpty
                        ? 'Henüz ödeme planı yok'
                        : 'Bu filtrede kayıt yok',
                    message: all.isEmpty
                        ? 'Bir iş için taksit, vade ya da çek/senet planı oluşturun; vadesi gelenleri buradan takip edin.'
                        : null,
                    actionLabel: all.isEmpty ? 'Taksit planı oluştur' : null,
                    onAction: all.isEmpty
                        ? () => context.push('${Routes.invoicesVat}/plan/new')
                        : null,
                  ),
                ),
              ],
            );
          }
          // Proje/müşteri başına grupla.
          final groups = <String, List<ScheduleItem>>{};
          for (final s in rows) {
            groups
                .putIfAbsent(
                  s.projectId ?? s.offerId ?? s.invoiceId ?? s.id,
                  () => [],
                )
                .add(s);
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              header,
              for (final g in groups.values)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.sm,
                    Space.lg,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.sm),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                g.first.displayWho,
                                style: context.text.titleSmall,
                              ),
                            ),
                            Text(
                              Money.sum(
                                g
                                    .where((s) => s.isPending)
                                    .map((s) => s.amount),
                              ).format(),
                              style: context.text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      for (final s in g) ScheduleRowTile(item: s),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
