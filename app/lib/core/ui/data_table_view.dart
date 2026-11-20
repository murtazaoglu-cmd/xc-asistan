// Geniş ekran (web) tablo görünümü: sıralanabilir sütunlar, satır üzerine gelince vurgu, Tab ile
// satır gezintisi, Enter/Boşluk ile açma, görünür odak halkası, el imleci, kısaltılmış hücrede ipucu
// (tooltip) ve CSV indirme / yazdırma. Tek kaynak: mobildeki liste kartlarının yerine geniş ekranda
// KULLANILIR; veri ve eylemler aynıdır (onRowTap mobildeki dokunmayla aynı rotayı açar).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import '../util/csv.dart';
import '../web/browser.dart';
import 'focus_ring.dart';

/// Tablo sütunu tanımı.
class DataColumnSpec<T> {
  const DataColumnSpec({
    required this.label,
    required this.text,
    this.cell,
    this.sortKey,
    this.flex = 1,
    this.width,
    this.numeric = false,
  });

  final String label;

  /// Hücrenin düz metni: CSV, yazdırma, ipucu ve varsayılan gösterim için.
  final String Function(T item) text;

  /// Özel gösterim (rozet, tutar vb.). Yoksa [text] kısaltılarak çizilir.
  final Widget Function(BuildContext context, T item)? cell;

  /// Sıralama anahtarı (num / DateTime / String / null). Verilmezse sütun sıralanamaz.
  final Object? Function(T item)? sortKey;
  final int flex;

  /// Sabit genişlik (verilirse [flex] yok sayılır).
  final double? width;

  /// Sayısal (sağa yaslı).
  final bool numeric;
}

int compareForSort(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1; // boşlar hep sonda
  if (b == null) return -1;
  if (a is num && b is num) return a.compareTo(b);
  if (a is DateTime && b is DateTime) return a.compareTo(b);
  if (a is bool && b is bool) return a == b ? 0 : (a ? -1 : 1);
  return _trKey(a.toString()).compareTo(_trKey(b.toString()));
}

String _trKey(String s) {
  const map = {
    'ç': 'c', 'Ç': 'c', 'ğ': 'g', 'Ğ': 'g', 'ı': 'i', 'İ': 'i', 'I': 'i',
    'ö': 'o', 'Ö': 'o', 'ş': 's', 'Ş': 's', 'ü': 'u', 'Ü': 'u', //
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(map[ch] ?? ch.toLowerCase());
  }
  return b.toString();
}

class DataTableView<T> extends StatefulWidget {
  const DataTableView({
    super.key,
    required this.items,
    required this.columns,
    this.onRowTap,
    this.title,
    this.fileName = 'liste',
    this.showExport,
    this.initialSort,
    this.initialAscending = true,
    this.isSelected,
    this.footer,
    this.rowSemanticLabel,
    this.trailingBuilder,
    this.trailingWidth = 48,
  });

  final List<T> items;
  final List<DataColumnSpec<T>> columns;
  final void Function(T item)? onRowTap;

  /// Yazdırma başlığı.
  final String? title;

  /// CSV dosya adı (uzantısız).
  final String fileName;

  /// CSV/yazdır düğmeleri; null → yalnız web'de.
  final bool? showExport;

  /// Varsayılan sıralama sütunu (sütun sırası).
  final int? initialSort;
  final bool initialAscending;
  final bool Function(T item)? isSelected;

  /// Tablonun altı (toplam satırı vb.).
  final Widget? footer;
  final String Function(T item)? rowSemanticLabel;

  /// Satır sonu eylemi (menü düğmesi vb.).
  final Widget Function(BuildContext context, T item)? trailingBuilder;
  final double trailingWidth;

  @override
  State<DataTableView<T>> createState() => _DataTableViewState<T>();
}

class _DataTableViewState<T> extends State<DataTableView<T>> {
  int? _sort;
  bool _asc = true;

  @override
  void initState() {
    super.initState();
    _sort = widget.initialSort;
    _asc = widget.initialAscending;
  }

  List<T> get _rows {
    final s = _sort;
    if (s == null || s >= widget.columns.length) return widget.items;
    final key = widget.columns[s].sortKey;
    if (key == null) return widget.items;
    final list = [...widget.items];
    list.sort((a, b) {
      final r = compareForSort(key(a), key(b));
      // Boşlar yönden bağımsız sonda kalsın.
      if (key(a) == null || key(b) == null) return r;
      return _asc ? r : -r;
    });
    return list;
  }

  void _toggle(int i) => setState(() {
    if (_sort == i) {
      _asc = !_asc;
    } else {
      _sort = i;
      _asc = true;
    }
  });

  /// Tablonun okunabilir en küçük genişliği: sabit sütunlar + esnek sütun başına 96 dp + satır sonu eylemi.
  double get _minWidth {
    var w = widget.trailingBuilder == null ? 0.0 : widget.trailingWidth;
    for (final c in widget.columns) {
      w += c.width ?? (c.flex * 96.0);
    }
    return w;
  }

  List<List<String>> _textRows(List<T> rows) => [
    for (final r in rows) [for (final c in widget.columns) c.text(r)],
  ];

  Future<void> _csv() async {
    final rows = _rows;
    final ok = await browserDownload(
      Csv.bytes([for (final c in widget.columns) c.label], _textRows(rows)),
      '${widget.fileName}.csv',
      'text/csv;charset=utf-8',
    );
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${widget.fileName}.csv indirildi (${rows.length} satır).'
              : 'Bu platformda dosya indirilemiyor.',
        ),
      ),
    );
  }

  void _print() {
    final ok = browserPrintTable(widget.title ?? widget.fileName, [
      for (final c in widget.columns) c.label,
    ], _textRows(_rows));
    if (!ok && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Yazdırma bu platformda kullanılamıyor.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _rows;
    final export = widget.showExport ?? kIsWeb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (export)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${rows.length} kayıt',
                    style: context.text.bodySmall?.copyWith(
                      color: c.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('table-csv'),
                  onPressed: rows.isEmpty ? null : _csv,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('CSV indir'),
                ),
                TextButton.icon(
                  key: const ValueKey('table-print'),
                  onPressed: rows.isEmpty ? null : _print,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Yazdır'),
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, c) {
            // Sütunlar sığmıyorsa (dar pencere) tablo yatay kaydırılır; sütunlar ezilmez.
            final minW = _minWidth;
            final scroll = c.maxWidth < minW;
            final inner = FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderRow<T>(
                    columns: widget.columns,
                    sort: _sort,
                    asc: _asc,
                    onSort: _toggle,
                    trailingWidth: widget.trailingBuilder == null
                        ? 0
                        : widget.trailingWidth,
                  ),
                  const Divider(height: 1),
                  for (var i = 0; i < rows.length; i++) ...[
                    _DataRow<T>(
                      index: i,
                      item: rows[i],
                      columns: widget.columns,
                      onTap: widget.onRowTap,
                      selected: widget.isSelected?.call(rows[i]) ?? false,
                      semanticLabel: widget.rowSemanticLabel?.call(rows[i]),
                      trailing: widget.trailingBuilder,
                      trailingWidth: widget.trailingWidth,
                    ),
                    if (i < rows.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            );
            return Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: scroll
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: minW, child: inner),
                    )
                  : inner,
            );
          },
        ),
        if (widget.footer != null) ...[
          const SizedBox(height: Space.sm),
          widget.footer!,
        ],
      ],
    );
  }
}

Widget _sized<T>(DataColumnSpec<T> col, Widget child) => col.width != null
    ? SizedBox(width: col.width, child: child)
    : Expanded(flex: col.flex, child: child);

class _HeaderRow<T> extends StatelessWidget {
  const _HeaderRow({
    required this.columns,
    required this.sort,
    required this.asc,
    required this.onSort,
    required this.trailingWidth,
  });
  final List<DataColumnSpec<T>> columns;
  final int? sort;
  final bool asc;
  final void Function(int) onSort;
  final double trailingWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = context.text.labelLarge?.copyWith(
      color: c.onSurfaceVariant,
      fontWeight: TypeTokens.semiBold,
    );
    return Container(
      color: c.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            _sized(
              columns[i],
              _HeaderCell(
                label: columns[i].label,
                style: style,
                numeric: columns[i].numeric,
                sortable: columns[i].sortKey != null,
                active: sort == i,
                asc: asc,
                onTap: () => onSort(i),
              ),
            ),
          if (trailingWidth > 0) SizedBox(width: trailingWidth),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.style,
    required this.numeric,
    required this.sortable,
    required this.active,
    required this.asc,
    required this.onTap,
  });
  final String label;
  final TextStyle? style;
  final bool numeric;
  final bool sortable;
  final bool active;
  final bool asc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 12),
      child: Row(
        mainAxisAlignment: numeric
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(child: text),
          if (sortable) ...[
            const SizedBox(width: 4),
            Icon(
              active
                  ? (asc ? Icons.arrow_upward : Icons.arrow_downward)
                  : Icons.unfold_more,
              size: 16,
              color: active ? context.colors.primary : style?.color,
            ),
          ],
        ],
      ),
    );
    if (!sortable) return inner;
    return Semantics(
      button: true,
      sortKey: null,
      label: '$label sütununa göre sırala',
      child: Tooltip(
        message: active
            ? '$label: ${asc ? 'artan' : 'azalan'} sıralı. Tersine çevirmek için tıklayın'
            : '$label sütununa göre sırala',
        child: InkWell(
          key: ValueKey('sort-$label'),
          onTap: onTap,
          child: inner,
        ),
      ),
    );
  }
}

class _DataRow<T> extends StatelessWidget {
  const _DataRow({
    required this.index,
    required this.item,
    required this.columns,
    required this.onTap,
    required this.selected,
    required this.semanticLabel,
    required this.trailing,
    required this.trailingWidth,
  });
  final int index;
  final T item;
  final List<DataColumnSpec<T>> columns;
  final void Function(T)? onTap;
  final bool selected;
  final String? semanticLabel;
  final Widget Function(BuildContext, T)? trailing;
  final double trailingWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          for (final col in columns)
            _sized(
              col,
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                child: Align(
                  alignment: col.numeric
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child:
                      col.cell?.call(context, item) ??
                      Tooltip(
                        message: col.text(item),
                        waitDuration: const Duration(milliseconds: 600),
                        child: Text(
                          col.text(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: col.numeric
                              ? TextAlign.right
                              : TextAlign.left,
                          style: context.text.bodyMedium,
                        ),
                      ),
                ),
              ),
            ),
          if (trailing != null)
            SizedBox(
              width: trailingWidth,
              child: Center(child: trailing!(context, item)),
            ),
        ],
      ),
    );
    return Semantics(
      container: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: selected
            ? c.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        child: onTap == null
            ? row
            : FocusRing(
                radius: 0,
                child: InkWell(
                  key: ValueKey('row-$index'),
                  onTap: () => onTap!(item),
                  hoverColor: c.primary.withValues(alpha: 0.06),
                  focusColor: c.primary.withValues(alpha: 0.10),
                  child: row,
                ),
              ),
      ),
    );
  }
}
