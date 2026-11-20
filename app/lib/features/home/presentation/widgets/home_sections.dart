// SAHİBİ: home ajanı. Bugün ekranının bölümleri. Her bölüm kendi boş durumunu bilir;
// yetki/rol kararı (hangi bölümün gösterileceği) ekranda verilir, burada yalnız çizim vardır.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/auth/auth_models.dart';
import '../../../../core/config/brand_profile.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/util/dates.dart';
import '../../../../core/util/formatters.dart';
import '../../../../core/util/money.dart';
import '../../../appointments/appointments_routes.dart';
import '../../../appointments/data/appointment_models.dart';
import '../../../appointments/data/tr_text.dart';
import '../../../appointments/presentation/appointment_card.dart';
import '../../application/home_controller.dart';
import '../../data/home_insights.dart';
import '../../data/home_models.dart';

String greetingFor(DateTime now) {
  final h = Ist.wall(now).hour;
  if (h < 5) return 'İyi geceler';
  if (h < 12) return 'Günaydın';
  if (h < 18) return 'İyi günler';
  return 'İyi akşamlar';
}

class HomeGreeting extends StatelessWidget {
  const HomeGreeting({
    super.key,
    required this.name,
    required this.now,
    this.updatedAt,
  });
  final String name;
  final DateTime now;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.isEmpty ? greetingFor(now) : '${greetingFor(now)}, $name',
          style: context.text.headlineSmall,
        ),
        Text(
          '${Fmt.dayHeading(now)}'
          '${updatedAt == null ? '' : ' · Güncellendi ${Fmt.time(updatedAt!)}'}',
          style: context.text.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Son yenileme başarısızsa: eski veri gösterilirken uyarı şeridi.
class StaleBanner extends StatelessWidget {
  const StaleBanner({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ex = AppException.from(error);
    final offline = ex.isNetwork;
    final x = context.xc;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: x.warningContainer,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: [
            Icon(
              offline ? Icons.cloud_off_outlined : Icons.sync_problem_outlined,
              color: x.onWarning,
              size: Sizes.iconSm,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                offline
                    ? 'Bağlantı yok. Son alınan bilgiler gösteriliyor.'
                    : 'Güncellenemedi: ${ex.message}',
                style: context.text.bodyMedium?.copyWith(color: x.onWarning),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Yenile')),
          ],
        ),
      ),
    );
  }
}

/// Asistan Özeti: kural tabanlı satırlar (AiCard).
class AssistantSummaryCard extends StatelessWidget {
  const AssistantSummaryCard({super.key, required this.lines});
  final List<InsightLine> lines;

  static IconData _icon(InsightLine l) => switch (l.kind) {
    InsightKind.appointments => Icons.event_outlined,
    InsightKind.nextUp => Icons.arrow_forward,
    InsightKind.late => Icons.schedule,
    InsightKind.tomorrow => Icons.event_note_outlined,
    InsightKind.offers => Icons.request_quote_outlined,
    InsightKind.awaiting => Icons.hourglass_top,
    InsightKind.overdueProjects => Icons.warning_amber_rounded,
    InsightKind.receivables => Icons.payments_outlined,
    InsightKind.reminders => Icons.alarm,
    InsightKind.lowStock => Icons.inventory_2_outlined,
    InsightKind.calm => Icons.check_circle_outline,
  };

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    final main = lines.where(
      (l) => l.route != null && l.kind != InsightKind.calm,
    );
    final top = main.where((l) => l.level != InsightLevel.info).firstOrNull;
    return AiCard(
      kind: AiCardKind.summary,
      title: 'Günün özeti',
      onWhy: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bu özet nasıl hazırlandı?'),
          content: const Text(
            'Cümleler, uygulamadaki güncel kayıtlarınızdan (randevu, talep, '
            'gecikme, hatırlatıcı, stok, tahsilat) basit kurallarla ve sayarak '
            'üretilir. Yapay zekâ yorumu içermez.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
      actions: [
        if (top != null)
          AiCardAction('İncele', () => context.go(top.route!), primary: true),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _icon(l),
                    size: Sizes.iconSm,
                    color: l.level == InsightLevel.urgent
                        ? context.colors.error
                        : x.ai,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      l.text,
                      style: context.text.bodyMedium?.copyWith(
                        color: x.onAiContainer,
                        fontWeight: l.level == InsightLevel.urgent
                            ? FontWeight.w600
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 4'lü sayı kutuları: Randevu / Tahsilat / Teklif / Geciken iş. Yetkisi olmayan kutu HİÇ çizilmez.
class HomeStatTiles extends StatelessWidget {
  const HomeStatTiles({
    super.key,
    required this.summary,
    required this.caps,
    required this.terms,
  });
  final HomeSummary summary;
  final AppCapabilities caps;
  final Glossary terms;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    final todayCount = summary.today.where((a) => !a.isCancelled).length;
    final fin = summary.finance;
    final newOffers = summary.newOfferCount;
    // Dar kutuda uzun sözlük terimi ("Fiyat teklifi") kesilmesin diye kısa etiket kullanılır.
    final offerLabel = terms.offer.length <= 8 ? terms.offer : 'Teklif';
    final tiles = <Widget>[
      StatTile(
        label: terms.appointment,
        value: '$todayCount',
        icon: Icons.event_outlined,
        onTap: () => context.go(Routes.appointments),
      ),
      if (caps.homeFinance && fin != null)
        StatTile(
          label: 'Tahsilat',
          value: '${fin.receivableProjectCount}',
          icon: Icons.payments_outlined,
          color: x.success,
          onTap: caps.showFinance ? () => context.go(Routes.finance) : null,
        ),
      if (caps.offers && newOffers != null)
        StatTile(
          label: offerLabel,
          value: '$newOffers',
          icon: Icons.request_quote_outlined,
          color: x.warning,
          onTap: caps.showJobs ? () => context.go(Routes.jobs) : null,
        ),
      if (caps.projects)
        StatTile(
          label: 'Geciken ${trLower(terms.job)}',
          value: '${summary.overdueProjectCount}',
          icon: Icons.warning_amber_rounded,
          color: summary.overdueProjectCount > 0
              ? context.colors.error
              : context.colors.primary,
          onTap: caps.showJobs ? () => context.go(Routes.jobs) : null,
        ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final scaled = MediaQuery.textScalerOf(context).scale(16) > 20.8;
        final cols = (c.maxWidth < 340 || scaled)
            ? (tiles.length > 2 ? 2 : tiles.length)
            : tiles.length;
        final w = (c.maxWidth - Space.sm * (cols - 1)) / cols;
        return Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

/// Bugün/Yarın randevu bölümü.
class AppointmentsSection extends ConsumerWidget {
  const AppointmentsSection({
    super.key,
    required this.title,
    required this.items,
    required this.emptyText,
    this.onAdd,
    this.showAll = true,
  });
  final String title;
  final List<Appointment> items;
  final String emptyText;
  final VoidCallback? onAdd;
  final bool showAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = items.where((a) => !a.isCancelled).toList();
    return SectionCard(
      title: visible.isEmpty ? title : '$title (${visible.length})',
      trailing: showAll
          ? TextButton(
              onPressed: () => context.go(Routes.appointments),
              child: const Text('Tümü'),
            )
          : null,
      child: visible.isEmpty
          ? Row(
              children: [
                Expanded(child: Text(emptyText)),
                if (onAdd != null)
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('Ekle'),
                  ),
              ],
            )
          : Column(
              children: [
                for (final a in visible) ...[
                  AppointmentCard(
                    key: ValueKey(a.id),
                    appointment: a,
                    onTap: () => context.push(Routes.appointment(a.id)),
                  ),
                  const SizedBox(height: Space.sm),
                ],
              ],
            ),
    );
  }
}

class NewOffersSection extends ConsumerWidget {
  const NewOffersSection({
    super.key,
    required this.summary,
    required this.canOpen,
  });
  final HomeSummary summary;
  final bool canOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    return SectionCard(
      title:
          'Yeni ${trLower(terms.offer)} talepleri (${summary.newOfferCount ?? 0})',
      trailing: canOpen
          ? TextButton(
              onPressed: () => context.go(Routes.jobs),
              child: const Text('Tümü'),
            )
          : null,
      child: Column(
        children: [
          for (final o in summary.newOffers)
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    onTap: canOpen
                        ? () => context.push(Routes.offer(o.id))
                        : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: Sizes.minTouch + 8,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.xs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(o.name, style: context.text.titleSmall),
                            Text(
                              [
                                if (o.service != null) o.service!,
                                if (o.region != null) o.region!,
                                if (o.createdAt != null)
                                  Fmt.relativeDate(o.createdAt!),
                              ].join(' · '),
                              style: context.text.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (o.phone != null)
                  SizedBox(
                    width: Sizes.minTouch,
                    child: PhoneActions(
                      phone: o.phone,
                      name: o.name,
                      child: const Center(child: Icon(Icons.phone_outlined)),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class OverdueProjectsSection extends ConsumerWidget {
  const OverdueProjectsSection({
    super.key,
    required this.summary,
    required this.canOpen,
  });
  final HomeSummary summary;
  final bool canOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    return SectionCard(
      title: 'Geciken ${trLower(terms.jobs)} (${summary.overdueProjectCount})',
      child: Column(
        children: [
          for (final p in summary.overdueProjects)
            InkWell(
              borderRadius: BorderRadius.circular(Radii.sm),
              onTap: canOpen ? () => context.push(Routes.project(p.id)) : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: Sizes.minTouch + 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              if (p.code != null) p.code!,
                              p.customerName,
                            ].join(' · '),
                            style: context.text.titleSmall,
                          ),
                          Text(
                            [
                              if (p.service != null) p.service!,
                              if (p.daysOverdue > 0)
                                '${p.daysOverdue} gün gecikti'
                              else
                                'Bitiş tarihi geçti',
                            ].join(' · '),
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusChip.stage(p.stage),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Hatırlatıcılar: gecikmişler önce. Tamamla (geri al'lı) ve Ertele eylemleri.
class RemindersSection extends ConsumerWidget {
  const RemindersSection({super.key, required this.summary});
  final HomeSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = [...summary.remindersOverdue, ...summary.remindersToday];
    final ctrl = ref.read(homeControllerProvider.notifier);

    void fail(Object e) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(AppException.from(e).message)));

    Future<void> complete(HomeReminder r) async {
      try {
        await ctrl.completeReminder(r);
      } catch (e) {
        if (context.mounted) fail(e);
        return;
      }
      if (!context.mounted) return;
      UndoSnackbar.show(
        context,
        message: 'Hatırlatıcı tamamlandı.',
        onUndo: () async {
          try {
            await ctrl.reopenReminder(r.id);
          } catch (e) {
            if (context.mounted) fail(e);
          }
        },
      );
    }

    Future<void> snooze(HomeReminder r, SnoozeChoice c) async {
      try {
        await ctrl.snoozeReminder(r, c.at);
      } catch (e) {
        if (context.mounted) fail(e);
        return;
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Ertelendi: ${Fmt.relativeDateTime(c.at)}')),
        );
    }

    return SectionCard(
      title: 'Hatırlatıcılar (${items.length})',
      child: Column(
        children: [
          for (final r in items)
            Padding(
              key: ValueKey('rem-${r.id}'),
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: [
                  Icon(
                    r.overdue ? Icons.alarm_off_outlined : Icons.alarm,
                    color: r.overdue
                        ? context.colors.error
                        : context.colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title, style: context.text.titleSmall),
                        Text(
                          [
                            if (r.overdue) 'Gecikti',
                            DateText.format(
                              r.remindAt,
                              DateTextMode.relativeDateTime,
                            ),
                            if (r.customerName != null) r.customerName!,
                            if (r.projectCode != null) r.projectCode!,
                          ].join(' · '),
                          style: context.text.bodySmall?.copyWith(
                            color: r.overdue
                                ? context.colors.error
                                : context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tamamla',
                    icon: const Icon(Icons.check_circle_outline),
                    onPressed: () => complete(r),
                  ),
                  PopupMenuButton<SnoozeChoice>(
                    tooltip: 'Ertele',
                    icon: const Icon(Icons.snooze),
                    onSelected: (c) => snooze(r, c),
                    itemBuilder: (_) => [
                      for (final c in reminderSnoozeChoices(Ist.now()))
                        PopupMenuItem(
                          value: c,
                          height: Sizes.minTouch,
                          child: Text(c.label),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class LowStockSection extends ConsumerWidget {
  const LowStockSection({
    super.key,
    required this.summary,
    required this.canOpen,
  });
  final HomeSummary summary;
  final bool canOpen;

  static String _n(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    return SectionCard(
      title: 'Düşük ${trLower(terms.stock)} (${summary.lowStockCount})',
      onTap: canOpen ? () => context.go(Routes.stock) : null,
      child: Column(
        children: [
          for (final m in summary.lowStock.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: Sizes.iconSm),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(m.name)),
                  Text(
                    '${_n(m.stockQuantity)} / ${_n(m.minStock)} ${m.unit}',
                    style: context.text.bodyMedium?.copyWith(
                      color: m.stockQuantity <= 0
                          ? context.colors.error
                          : context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Tahsilat özeti: yalnız finans verisi gelen roller (A/M/O).
class FinanceSection extends ConsumerWidget {
  const FinanceSection({
    super.key,
    required this.finance,
    required this.canOpen,
  });
  final HomeFinance finance;
  final bool canOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    Widget cell(String label, Money value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.bodySmall),
          MoneyText(
            value,
            hideZeroKurus: true,
            style: context.text.titleMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
    return SectionCard(
      title: 'Tahsilat özeti',
      onTap: canOpen ? () => context.go(Routes.finance) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              cell(
                'Bu hafta',
                finance.collectedThisWeek,
                color: context.xc.success,
              ),
              cell(
                'Bu ay',
                finance.collectedThisMonth,
                color: context.xc.success,
              ),
              cell('Alacak', finance.receivableTotal),
            ],
          ),
          if (finance.topReceivables.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Text(
              'En yüksek alacaklar (${trLower(terms.job)})',
              style: context.text.labelLarge,
            ),
            for (final r in finance.topReceivables.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          if (r.code != null) r.code!,
                          r.customerName,
                        ].join(' · '),
                      ),
                    ),
                    MoneyText(r.balance, hideZeroKurus: true),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Boş gün: bugün yapılacak/izlenecek hiçbir şey yok.
class QuietDayCard extends ConsumerWidget {
  const QuietDayCard({super.key, required this.canCreate});
  final bool canCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        child: EmptyState(
          icon: Icons.wb_sunny_outlined,
          title: 'Bugün sakin bir gün',
          message:
              'Planlı ${trLower(terms.appointment)}, bekleyen talep ya da hatırlatıcı yok.',
          actionLabel: canCreate ? '${terms.appointment} ekle' : null,
          onAction: canCreate
              ? () => context.push(
                  AppointmentsRoutes.newPath(day: Ist.startOfDay(Ist.now())),
                )
              : null,
        ),
      ),
    );
  }
}

class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Yükleniyor',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.lg),
        children: const [
          SkeletonBox(height: 28, width: 220),
          SizedBox(height: Space.sm),
          SkeletonBox(height: 16, width: 160),
          SizedBox(height: Space.lg),
          SkeletonBox(height: 120, radius: Radii.card),
          SizedBox(height: Space.lg),
          SkeletonBox(height: 96, radius: Radii.card),
          SizedBox(height: Space.lg),
          SkeletonBox(height: 160, radius: Radii.card),
        ],
      ),
    );
  }
}
