// Mobil okunabilir aylık grafik: en çok 6 ay, iki seri (gelir/gider), kısa eksen etiketleri,
// büyük dokunma alanı. Dokunulan ay altta "Seçili ay" kartında büyük yazıyla gösterilir
// (araç ipucu yerine); tablo görünümü erişilebilirlik içindir.
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/money.dart';
import '../data/finance_calc.dart';

/// Eksen adımı: "güzel" sayılar (1, 2, 2.5, 5 × 10^k) ile en çok ~4 çizgi.
double niceAxisStep(double maxValue, {int lines = 4}) {
  if (maxValue <= 0) return 1;
  final raw = maxValue / lines;
  final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / exp;
  final nice = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 2.5 ? 2.5 : (f <= 5 ? 5 : 10)));
  return nice * exp;
}

class FinanceChart extends StatefulWidget {
  const FinanceChart({super.key, required this.months});

  /// Eskiden yeniye, en çok [FinanceCalc.maxChartMonths] ay.
  final List<ChartMonth> months;

  @override
  State<FinanceChart> createState() => _FinanceChartState();
}

class _FinanceChartState extends State<FinanceChart> {
  int? _selected;

  int get _index {
    final s = _selected;
    if (s != null && s < widget.months.length) return s;
    return widget.months.length - 1;
  }

  @override
  void didUpdateWidget(FinanceChart old) {
    super.didUpdateWidget(old);
    if (old.months.length != widget.months.length ||
        (widget.months.isNotEmpty &&
            old.months.isNotEmpty &&
            old.months.last.month != widget.months.last.month)) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final months = widget.months;
    final x = context.xc;
    final scheme = context.colors;
    if (months.isEmpty || !months.any((m) => m.hasData)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.lg),
        child: Text(
          'Son aylarda kayıt yok. Ödeme ya da gider eklediğinizde grafik burada görünür.',
        ),
      );
    }
    final maxTl = months
        .map((m) => math.max(m.revenue.toTl(), m.expense.toTl()))
        .fold<double>(0, math.max);
    final step = niceAxisStep(maxTl);
    final maxY = (maxTl / step).ceil().clamp(1, 1000) * step;
    final sel = months[_index];
    final total = Money.sum(months.map((m) => m.revenue));
    final totalExp = Money.sum(months.map((m) => m.expense));
    final first = months.first.month;
    final last = months.last.month;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gösterge grafiğin ÜSTÜNDE, tek satır, renk + metin.
        Wrap(
          spacing: Space.lg,
          runSpacing: Space.xs,
          children: [
            _LegendItem(color: x.success, label: 'Gelir'),
            _LegendItem(color: scheme.error, label: 'Gider (işletme)'),
          ],
        ),
        const SizedBox(height: Space.md),
        Semantics(
          container: true,
          label:
              '${first.mediumLabel} – ${last.mediumLabel} aylık grafik: toplam gelir ${total.format(hideZeroKurus: true)}, toplam gider ${totalExp.format(hideZeroKurus: true)}',
          child: ExcludeSemantics(
            child: SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  minY: 0,
                  alignment: BarChartAlignment.spaceAround,
                  groupsSpace: Space.sm,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: step,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: scheme.outlineVariant, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 56,
                        interval: step,
                        getTitlesWidget: (v, meta) {
                          if (v == meta.max && v != maxY) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              FinanceCalc.compact(Money.fromTl(v)),
                              style: context.text.bodySmall,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 ||
                              i >= months.length ||
                              v != i.toDouble()) {
                            return const SizedBox.shrink();
                          }
                          final m = months[i].month;
                          // Yıl: pencerenin ilk ayında ve Ocak'ta.
                          final showYear = i == 0 || m.month == 1;
                          return SideTitleWidget(
                            meta: meta,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  m.shortLabel,
                                  style: context.text.bodySmall?.copyWith(
                                    fontWeight: i == _index
                                        ? TypeTokens.bold
                                        : TypeTokens.regular,
                                    color: i == _index
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                                if (showYear)
                                  Text(
                                    '${m.year}',
                                    style: context.text.bodySmall?.copyWith(
                                      fontSize: TypeTokens.caption,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchExtraThreshold: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 220,
                    ),
                    handleBuiltInTouches: false,
                    touchCallback: (event, response) {
                      final spot = response?.spot;
                      if (event is FlTapUpEvent && spot != null) {
                        setState(() => _selected = spot.touchedBarGroupIndex);
                      }
                    },
                  ),
                  barGroups: [
                    for (var i = 0; i < months.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 4,
                        barRods: [
                          BarChartRodData(
                            toY: months[i].revenue.toTl(),
                            width: 14,
                            color: x.success.withValues(
                              alpha: i == _index ? 1 : 0.55,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                          BarChartRodData(
                            toY: months[i].expense.toTl(),
                            width: 14,
                            color: scheme.error.withValues(
                              alpha: i == _index ? 1 : 0.55,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        _SelectedMonthCard(month: sel),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Tablo olarak göster'),
            children: [
              Table(
                columnWidths: const {0: FlexColumnWidth(1.1)},
                children: [
                  TableRow(
                    children: [
                      for (final h in const ['Ay', 'Gelir', 'Gider', 'Net'])
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Space.sm,
                          ),
                          child: Text(
                            h,
                            textAlign: h == 'Ay'
                                ? TextAlign.start
                                : TextAlign.end,
                            style: context.text.labelLarge,
                          ),
                        ),
                    ],
                  ),
                  for (final m in months)
                    TableRow(
                      children: [
                        _cell(context, m.month.mediumLabel, start: true),
                        _cell(context, FinanceCalc.compact(m.revenue)),
                        _cell(context, FinanceCalc.compact(m.expense)),
                        _cell(
                          context,
                          FinanceCalc.compact(m.net),
                          color: m.net.isNegative ? scheme.error : null,
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    String t, {
    bool start = false,
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.sm),
    child: Text(
      t,
      textAlign: start ? TextAlign.start : TextAlign.end,
      style: context.text.bodyMedium?.copyWith(color: color),
    ),
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: Space.sm),
      Text(label, style: context.text.bodyMedium),
    ],
  );
}

class _SelectedMonthCard extends StatelessWidget {
  const _SelectedMonthCard({required this.month});
  final ChartMonth month;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: month.hasData
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(month.month.mediumLabel, style: context.text.titleSmall),
                const SizedBox(height: Space.xs),
                _row(context, 'Gelir', month.revenue, context.xc.success),
                _row(context, 'Gider', month.expense, scheme.error),
                _row(
                  context,
                  'Net',
                  month.net,
                  month.net.isNegative ? scheme.error : null,
                ),
              ],
            )
          : Text(
              '${month.month.mediumLabel}: bu ay kayıt yok.',
              style: context.text.bodyMedium,
            ),
    );
  }

  Widget _row(BuildContext context, String l, Money m, Color? c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(l, style: context.text.bodyLarge)),
        MoneyText(m, style: context.text.titleMedium?.copyWith(color: c)),
      ],
    ),
  );
}
