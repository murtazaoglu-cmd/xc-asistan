// Para grafiği (tasarım ekran 11 stili: mavi Gelir + amber Gider çubukları, hafif ızgara,
// grafiğin ÜSTÜNDE açıklama). Mobil okunabilirlik kuralları:
//  - en çok 6 ay görünür, geçmiş yatay kaydırılır (en yeni sağda açılır)
//  - yalnız iki seri (Gelir, Gider); kâr ve ev gideri "Seçili dönem" kutusunda
//  - eksen etiketleri çakışmaz: sabit slot, kısa ay adı, kısa para ("₺12 B")
//  - dokununca değer kutusu; boş ay "kayıt yok" der (₺0 yazmaz)
//  - renk tek başına anlam taşımaz: etiket + dolu/çerçeveli şekil + tablo görünümü
import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/money.dart';
import '../data/report_charts.dart';

class MoneyBarChart extends StatefulWidget {
  const MoneyBarChart({super.key, required this.data, this.height = 220});

  final MoneyChartData data;
  final double height;

  @override
  State<MoneyBarChart> createState() => _MoneyBarChartState();
}

class _MoneyBarChartState extends State<MoneyBarChart> {
  static const double _axisWidth = 56;
  static const double _bottomReserved = 40;
  static const double _minSlot = 48;

  late int _selected = widget.data.defaultSelected;
  bool _table = false;

  @override
  void didUpdateWidget(MoneyBarChart old) {
    super.didUpdateWidget(old);
    final a = old.data.bars.map((b) => b.key).join(','),
        b = widget.data.bars.map((b) => b.key).join(',');
    if (a != b) _selected = widget.data.defaultSelected;
    if (_selected >= widget.data.bars.length) {
      _selected = widget.data.defaultSelected;
    }
  }

  void _select(int i) {
    final n = widget.data.bars.length;
    if (n == 0) return;
    setState(() => _selected = i.clamp(0, n - 1));
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final bars = data.bars;
    if (bars.isEmpty) return const SizedBox.shrink();
    final maxTl = bars.fold<double>(
      0,
      (m, b) => [
        m,
        b.revenue.toTl(),
        b.expense.toTl(),
      ].reduce((a, c) => a > c ? a : c),
    );
    final scale = ChartScale.nice(maxTl);
    final totals = data.visibleTotals();
    final semantic =
        'Gelir ve gider grafiği. Son ${data.visibleCount < bars.length ? data.visibleCount : bars.length} dönem: toplam gelir ${totals.revenue.format(hideZeroKurus: true)}, işletme gideri ${totals.expense.format(hideZeroKurus: true)}.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Legend(),
        const SizedBox(height: Space.md),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Semantics(
            container: true,
            label: semantic,
            child: ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, c) {
                  final viewport = c.maxWidth - _axisWidth;
                  final shown = data.visibleCount < bars.length
                      ? data.visibleCount
                      : bars.length;
                  var slot = viewport / shown;
                  if (slot < _minSlot) slot = _minSlot;
                  final width = slot * bars.length;
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _YAxis(
                          scale: scale,
                          height: widget.height,
                          bottomReserved: _bottomReserved,
                          width: _axisWidth,
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            key: const Key('chart-scroll'),
                            scrollDirection: Axis.horizontal,
                            reverse: true, // en yeni dönem sağda açılır
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (d) =>
                                  _select((d.localPosition.dx / slot).floor()),
                              child: SizedBox(
                                width: width < viewport ? viewport : width,
                                height: widget.height,
                                child: _chart(context, bars, scale, slot),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        _ValueBox(
          bar: bars[_selected],
          canPrev: _selected > 0,
          canNext: _selected < bars.length - 1,
          onPrev: () => _select(_selected - 1),
          onNext: () => _select(_selected + 1),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _table = !_table),
            icon: Icon(_table ? Icons.expand_less : Icons.table_rows_outlined),
            label: Text(_table ? 'Tabloyu gizle' : 'Tablo olarak göster'),
          ),
        ),
        if (_table) _DataTable(bars: bars, selected: _selected, onTap: _select),
      ],
    );
  }

  Widget _chart(
    BuildContext context,
    List<ChartBar> bars,
    ChartScale scale,
    double slot,
  ) {
    final colors = context.colors;
    final x = context.xc;
    final rodW = (slot * 0.24).clamp(8.0, 18.0);
    double h(double tl) =>
        tl <= 0 ? 0 : (tl < scale.max * 0.025 ? scale.max * 0.025 : tl);
    final groups = <BarChartGroupData>[
      for (var i = 0; i < bars.length; i++)
        BarChartGroupData(
          x: i,
          barsSpace: 4,
          barRods: [
            BarChartRodData(
              toY: h(bars[i].revenue.toTl()),
              width: rodW,
              color: colors.primary,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
            BarChartRodData(
              toY: h(bars[i].expense.toTl()),
              width: rodW,
              color: x.warning,
              borderSide: BorderSide(
                color: colors.onSurfaceVariant,
                width: bars[i].expense.isZero ? 0 : 1.2,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ],
        ),
    ];
    return Stack(
      children: [
        Positioned(
          left: _selected * slot + 2,
          width: slot - 4,
          top: 0,
          bottom: _bottomReserved,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(Radii.xs),
            ),
          ),
        ),
        BarChart(
          BarChartData(
            minY: 0,
            maxY: scale.max,
            alignment: BarChartAlignment.spaceAround,
            barGroups: groups,
            barTouchData: BarTouchData(enabled: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: scale.step,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: colors.outlineVariant, strokeWidth: 1),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border(bottom: BorderSide(color: colors.outline)),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: _bottomReserved,
                  interval: 1,
                  getTitlesWidget: (v, meta) {
                    final i = v.round();
                    if (i < 0 || i >= bars.length)
                      return const SizedBox.shrink();
                    final b = bars[i];
                    final sel = i == _selected;
                    final style = context.text.bodySmall?.copyWith(
                      fontSize: TypeTokens.caption,
                      height: 1.1,
                      fontWeight: sel ? TypeTokens.bold : TypeTokens.regular,
                      color: b.hasData
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                    );
                    return SideTitleWidget(
                      meta: meta,
                      space: 6,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(b.label, style: style),
                          if (b.yearLabel != null)
                            Text(
                              b.yearLabel!,
                              style: style?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontWeight: TypeTokens.regular,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _YAxis extends StatelessWidget {
  const _YAxis({
    required this.scale,
    required this.height,
    required this.bottomReserved,
    required this.width,
  });
  final ChartScale scale;
  final double height;
  final double bottomReserved;
  final double width;

  @override
  Widget build(BuildContext context) {
    final plotH = height - bottomReserved;
    final style = context.text.bodySmall?.copyWith(
      fontSize: TypeTokens.caption,
      color: context.colors.onSurfaceVariant,
    );
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i <= scale.ticks; i++)
            Positioned(
              top: plotH * (1 - i / scale.ticks) - 9,
              right: Space.sm,
              child: Text(
                CompactMoney.format(Money.fromTl(scale.step * i)),
                style: style,
                maxLines: 1,
              ),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget item(Widget swatch, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: Space.sm),
        Text(text, style: context.text.bodyMedium),
      ],
    );
    return Wrap(
      spacing: Space.lg,
      runSpacing: Space.xs,
      children: [
        item(
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          'Gelir',
        ),
        item(
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: context.xc.warning,
              border: Border.all(color: colors.onSurfaceVariant, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          'Gider (işletme)',
        ),
      ],
    );
  }
}

/// Seçili dönemin değerleri. Boş dönem "kayıt yok" der.
class _ValueBox extends StatelessWidget {
  const _ValueBox({
    required this.bar,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });
  final ChartBar bar;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final x = context.xc;
    final isMonth = bar.month != null;
    Widget row(Widget lead, String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          lead,
          const SizedBox(width: Space.sm),
          Expanded(child: Text(label, style: context.text.bodyLarge)),
          value,
        ],
      ),
    );
    Widget swatch(Color c, {bool outlined = false}) => Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: c,
        border: outlined
            ? Border.all(color: colors.onSurfaceVariant, width: 1.5)
            : null,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    final net = bar.net;
    return Container(
      key: const Key('value-box'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: isMonth ? 'Önceki ay' : 'Önceki yıl',
                onPressed: canPrev ? onPrev : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    bar.longLabel,
                    textAlign: TextAlign.center,
                    style: context.text.titleMedium,
                  ),
                ),
              ),
              IconButton(
                tooltip: isMonth ? 'Sonraki ay' : 'Sonraki yıl',
                onPressed: canNext ? onNext : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (!bar.hasData)
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Row(
                children: [
                  Icon(
                    Icons.event_busy_outlined,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      isMonth ? 'Bu ay kayıt yok.' : 'Bu yıl kayıt yok.',
                      style: context.text.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            row(
              swatch(colors.primary),
              'Gelir (tahsilat)',
              MoneyText(bar.revenue, style: context.text.titleSmall),
            ),
            row(
              swatch(x.warning, outlined: true),
              'Gider (işletme)',
              MoneyText(bar.expense, style: context.text.titleSmall),
            ),
            row(
              Icon(
                net.isNegative ? Icons.trending_down : Icons.trending_up,
                size: 18,
                color: net.isNegative ? colors.error : x.success,
              ),
              'Net kâr (işletme)',
              MoneyText(
                net,
                colorizeNegative: true,
                style: context.text.titleSmall,
              ),
            ),
            const Divider(height: Space.lg),
            row(
              Icon(
                Icons.home_outlined,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              'Ev giderleri (kâra dahil değil)',
              MoneyText(bar.homeExpense, style: context.text.bodyLarge),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ev giderleri dahil net',
                      style: context.text.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  MoneyText(
                    bar.netInclHome,
                    colorizeNegative: true,
                    style: context.text.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Aynı veri tablo olarak (ekran okuyucu ve kesin rakam için). Yeni dönem üstte.
class _DataTable extends StatelessWidget {
  const _DataTable({
    required this.bars,
    required this.selected,
    required this.onTap,
  });
  final List<ChartBar> bars;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final style = context.text.bodyMedium;
    final head = context.text.labelLarge;
    Widget cell(Widget child, {Alignment a = Alignment.centerRight}) => Padding(
      padding: const EdgeInsets.symmetric(
        vertical: Space.sm,
        horizontal: Space.xs,
      ),
      child: Align(alignment: a, child: child),
    );
    Widget money(Money m, {bool colorize = false}) => FittedBox(
      fit: BoxFit.scaleDown,
      child: MoneyText(
        m,
        hideZeroKurus: true,
        colorizeNegative: colorize,
        style: style,
      ),
    );
    return Table(
      key: const Key('chart-table'),
      columnWidths: const {
        0: FlexColumnWidth(1.1),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.2),
      },
      children: [
        TableRow(
          children: [
            cell(Text('Dönem', style: head), a: Alignment.centerLeft),
            cell(Text('Gelir', style: head)),
            cell(Text('Gider', style: head)),
            cell(Text('Net', style: head)),
          ],
        ),
        for (var i = bars.length - 1; i >= 0; i--)
          TableRow(
            decoration: BoxDecoration(
              color: i == selected ? context.colors.primaryContainer : null,
            ),
            children: [
              for (final c in [
                cell(
                  Text(
                    bars[i].month == null
                        ? bars[i].label
                        : '${bars[i].label} ${bars[i].year.toString().substring(2)}',
                    style: style,
                  ),
                  a: Alignment.centerLeft,
                ),
                if (bars[i].hasData) ...[
                  cell(money(bars[i].revenue)),
                  cell(money(bars[i].expense)),
                  cell(money(bars[i].net, colorize: true)),
                ] else ...[
                  cell(
                    Text(
                      'kayıt yok',
                      style: style?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  cell(const Text('')),
                  cell(const Text('')),
                ],
              ])
                InkWell(onTap: () => onTap(i), child: c),
            ],
          ),
      ],
    );
  }
}
