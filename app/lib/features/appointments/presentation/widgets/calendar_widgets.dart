// SAHİBİ: appointments ajanı. Hafta şeridi ve ay ızgarası. Günler İstanbul takvim günüdür;
// her gün "günün başlangıcı" (UTC an) ile temsil edilir. Hücreler ≥48 dp dokunma hedefidir.
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/util/dates.dart';
import '../../../../core/util/formatters.dart';
import '../../data/appointment_logic.dart';

String _semantic(DateTime day, int count) {
  final w = Ist.wall(day);
  final base =
      '${w.day} ${Fmt.monthsLong[w.month - 1]} ${Fmt.weekdaysLong[w.weekday - 1]}';
  return count == 0 ? base : '$base, $count randevu';
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.count,
    required this.onTap,
    this.dimmed = false,
    this.showWeekday = false,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final int count;
  final bool dimmed;
  final bool showWeekday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = Ist.wall(day);
    final c = context.colors;
    final fg = selected
        ? c.onPrimary
        : (dimmed ? c.onSurfaceVariant : c.onSurface);
    return Semantics(
      button: true,
      selected: selected,
      label: _semantic(day, count),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.minTouch + 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showWeekday)
                Text(
                  Fmt.weekdaysShort[w.weekday - 1],
                  style: context.text.bodySmall?.copyWith(
                    color: c.onSurfaceVariant,
                  ),
                ),
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? c.primary : null,
                  shape: BoxShape.circle,
                  border: isToday && !selected
                      ? Border.all(color: c.primary, width: 1.5)
                      : null,
                ),
                child: Text(
                  '${w.day}',
                  style: context.text.titleSmall?.copyWith(color: fg),
                ),
              ),
              SizedBox(
                height: 10,
                child: count > 0
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < (count > 3 ? 3 : count); i++)
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: c.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pzt..Paz hafta şeridi.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.selected,
    required this.counts,
    required this.onSelect,
    required this.now,
  });

  /// Seçili günün herhangi bir anı.
  final DateTime selected;

  /// Günün başlangıcı → randevu sayısı.
  final Map<DateTime, int> counts;
  final ValueChanged<DateTime> onSelect;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final days = weekDays(selected);
    final sel = Ist.startOfDay(selected);
    final today = Ist.startOfDay(now);
    return Row(
      children: [
        for (final d in days)
          Expanded(
            child: _DayCell(
              day: d,
              showWeekday: true,
              selected: d == sel,
              isToday: d == today,
              count: counts[d] ?? 0,
              onTap: () => onSelect(d),
            ),
          ),
      ],
    );
  }
}

/// Ay ızgarası (5-6 hafta). Ay dışı günler soluk.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.selected,
    required this.counts,
    required this.onSelect,
    required this.now,
  });

  final DateTime selected;
  final Map<DateTime, int> counts;
  final ValueChanged<DateTime> onSelect;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final days = monthGridDays(selected);
    final sel = Ist.startOfDay(selected);
    final today = Ist.startOfDay(now);
    final month = Ist.wall(selected).month;
    final rows = days.length ~/ 7;
    return Column(
      children: [
        Row(
          children: [
            for (final n in Fmt.weekdaysShort)
              Expanded(
                child: Center(
                  child: Text(
                    n,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: _DayCell(
                    day: days[r * 7 + c],
                    dimmed: Ist.wall(days[r * 7 + c]).month != month,
                    selected: days[r * 7 + c] == sel,
                    isToday: days[r * 7 + c] == today,
                    count: counts[days[r * 7 + c]] ?? 0,
                    onTap: () => onSelect(days[r * 7 + c]),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
