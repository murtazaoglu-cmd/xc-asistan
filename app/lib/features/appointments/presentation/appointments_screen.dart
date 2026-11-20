// SAHİBİ: appointments ajanı. Randevular: hafta şeridi + gün listesi (ay görünümüne geçiş),
// tek dokunuşla durum, ertele, telefon/adres eylemleri, boş/iskelet/hata durumları.
// Saha rolü yalnız kendi randevularını görür (assigned_user_id=me), ekleme/silme yok.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/formatters.dart';
import '../appointments_routes.dart';
import '../application/appointment_providers.dart';
import '../data/appointment_logic.dart';
import '../data/appointment_models.dart';
import '../data/tr_text.dart';
import 'appointment_card.dart';
import 'appointment_ui.dart';
import 'widgets/calendar_widgets.dart';

class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key, this.initialDay});

  /// Test/derin bağlantı için başlangıç günü (varsayılan: bugün).
  final DateTime? initialDay;

  @override
  ConsumerState<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  late DateTime _selected = Ist.startOfDay(widget.initialDay ?? Ist.now());
  bool _month = false;
  bool _mineFilter = false;

  AppointmentQuery _query(bool mine) => AppointmentQuery(
    _month ? monthGridRange(_selected) : Ist.weekRange(_selected),
    mine: mine,
  );

  void _select(DateTime day) => setState(() => _selected = Ist.startOfDay(day));

  void _shift(int delta) {
    final w = Ist.wall(_selected);
    setState(() {
      if (_month) {
        final next = Ist.fromWall(w.year, w.month + delta, 1);
        final now = Ist.now();
        _selected =
            (Ist.wall(next).month == Ist.wall(now).month &&
                Ist.wall(next).year == Ist.wall(now).year)
            ? Ist.startOfDay(now)
            : next;
      } else {
        _selected = Ist.fromWall(w.year, w.month, w.day + 7 * delta);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capabilitiesProvider);
    final terms = ref.watch(brandProfileProvider).terms;
    final isField = caps?.isField ?? false;
    final canCreate = (caps?.appointmentsCreate ?? false) && !isField;
    final mine = isField || _mineFilter;
    final query = _query(mine);
    final value = ref.watch(appointmentsRangeProvider(query));
    final hidden = ref.watch(hiddenAppointmentIdsProvider);
    final now = Ist.now();

    Future<void> refresh() async {
      ref.invalidate(appointmentsRangeProvider(query));
      try {
        await ref.read(appointmentsRangeProvider(query).future);
      } catch (_) {
        // hata ekranda gösterilir
      }
    }

    final w = Ist.wall(_selected);
    return AppScaffold(
      title: terms.appointments,
      actions: [
        IconButton(
          tooltip: 'Bugüne git',
          icon: const Icon(Icons.today_outlined),
          onPressed: () => _select(Ist.now()),
        ),
      ],
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              tooltip: '${terms.appointment} ekle',
              onPressed: () =>
                  context.push(AppointmentsRoutes.newPath(day: _selected)),
              icon: const Icon(Icons.add),
              label: Text('${terms.appointment} ekle'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.screenH,
              Space.sm,
              Space.screenH,
              0,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: _month ? 'Önceki ay' : 'Önceki hafta',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: Text(
                    '${Fmt.monthsLong[w.month - 1]} ${w.year}',
                    textAlign: TextAlign.center,
                    style: context.text.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: _month ? 'Sonraki ay' : 'Sonraki hafta',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shift(1),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.screenH),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -200) _shift(1);
                if (v > 200) _shift(-1);
              },
              child: _calendar(value, hidden, now),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.screenH,
              vertical: Space.sm,
            ),
            child: Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Hafta')),
                    ButtonSegment(value: true, label: Text('Ay')),
                  ],
                  selected: {_month},
                  onSelectionChanged: (s) => setState(() => _month = s.first),
                ),
                if (!isField)
                  FilterChip(
                    label: const Text('Yalnız benim'),
                    selected: _mineFilter,
                    onSelected: (v) => setState(() => _mineFilter = v),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _dayList(
              value: value,
              hidden: hidden,
              canCreate: canCreate,
              isField: isField,
              onRefresh: refresh,
              onRetry: () => ref.invalidate(appointmentsRangeProvider(query)),
            ),
          ),
        ],
      ),
    );
  }

  Map<DateTime, int> _counts(List<Appointment> items) => {
    for (final e in groupByDay(items.where((a) => !a.isCancelled)).entries)
      e.key: e.value.length,
  };

  Widget _calendar(
    AsyncValue<List<Appointment>> value,
    Set<String> hidden,
    DateTime now,
  ) {
    final items = (value.value ?? const <Appointment>[])
        .where((a) => !hidden.contains(a.id))
        .toList();
    final counts = _counts(items);
    return _month
        ? MonthGrid(
            selected: _selected,
            counts: counts,
            onSelect: _select,
            now: now,
          )
        : WeekStrip(
            selected: _selected,
            counts: counts,
            onSelect: _select,
            now: now,
          );
  }

  Widget _dayList({
    required AsyncValue<List<Appointment>> value,
    required Set<String> hidden,
    required bool canCreate,
    required bool isField,
    required Future<void> Function() onRefresh,
    required VoidCallback onRetry,
  }) {
    final terms = ref.watch(brandProfileProvider).terms;
    if (value.isLoading && !value.hasValue) {
      return const SkeletonList(itemCount: 3, itemHeight: 120);
    }
    if (value.hasError && !value.hasValue) {
      return PullToRefresh.fill(
        onRefresh: onRefresh,
        child: ErrorState(error: value.error, onRetry: onRetry),
      );
    }
    final all = value.value ?? const <Appointment>[];
    final day = Ist.dayRange(_selected);
    final items =
        all
            .where(
              (a) =>
                  !hidden.contains(a.id) &&
                  a.scheduledAt != null &&
                  day.contains(a.scheduledAt!),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
    final stale = value.hasError;

    final heading = Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Text(
        items.isEmpty
            ? dayHeadingText(_selected)
            : '${dayHeadingText(_selected)} · ${items.length}',
        style: context.text.titleSmall,
      ),
    );

    if (items.isEmpty) {
      return PullToRefresh.fill(
        onRefresh: onRefresh,
        child: EmptyState(
          icon: Icons.event_available_outlined,
          title: Ist.isSameDay(_selected, Ist.now())
              ? 'Bugün ${trLower(terms.appointment)} yok'
              : 'Bu gün için ${trLower(terms.appointment)} yok',
          message: canCreate
              ? 'İlk ${trLower(terms.appointment)} kaydını eklemek için dokunun.'
              : 'Yeni bir ${trLower(terms.appointment)} atandığında burada görünür.',
          actionLabel: canCreate ? '${terms.appointment} ekle' : null,
          onAction: canCreate
              ? () => context.push(AppointmentsRoutes.newPath(day: _selected))
              : null,
        ),
      );
    }

    return PullToRefresh(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Space.screenH,
          Space.lg,
          Space.screenH,
          96,
        ),
        children: [
          if (stale)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: StatusChip(
                label: 'Güncellenemedi, eski veri gösteriliyor',
                tone: StatusTone.warning,
                icon: Icons.cloud_off_outlined,
              ),
            ),
          heading,
          for (final a in items) ...[
            AppointmentCard(
              key: ValueKey(a.id),
              appointment: a,
              showAssignee: !isField,
              onTap: () => context.push(Routes.appointment(a.id)),
              onStatus: (x, s) =>
                  AppointmentUi.changeStatus(context, ref, x, s),
              onSnooze: (x) => AppointmentUi.snooze(context, ref, x),
            ),
            const SizedBox(height: Space.md),
          ],
        ],
      ),
    );
  }
}
