// Geniş ekran (web paneli) yerleşim yardımcıları. Mobil (< 720 dp) düzeni DEĞİŞTİRMEZ:
// dar alanda her şey tek sütunda, eskisi gibi dizilir.
import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import 'breakpoints.dart';

/// Çocukları kullanılabilir genişliğe göre 1 / 2 / 3 sütuna dağıtır (okuma sırası: soldan sağa, sonra
/// aşağı: çocuk i → sütun i % n). Dar alanda ([Breakpoints.twoColumn] altı) düz `Column`.
///
/// Kaydırma gövdesinin İÇİNDE kullanılır (yüksekliği içeriğe göre; kendi kaydırması yok).
/// [fullWidth] içindeki çocuklar tüm genişliği kaplar (ör. üstte sayı kutuları satırı).
class ResponsiveColumns extends StatelessWidget {
  const ResponsiveColumns({
    super.key,
    required this.children,
    this.gap = Space.md,
    this.maxColumns = 3,
    this.fullWidth = const [],
  });

  final List<Widget> children;
  final List<Widget> fullWidth;
  final double gap;
  final int maxColumns;

  /// Bu genişlikte kaç sütun.
  static int columnsFor(double width, {int max = 3}) {
    final n = width >= Breakpoints.threeColumn
        ? 3
        : (width >= Breakpoints.twoColumn ? 2 : 1);
    return n > max ? max : n;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final n = columnsFor(c.maxWidth, max: maxColumns);
      final top = [
        for (final w in fullWidth) ...[w, SizedBox(height: gap)],
      ];
      if (n == 1) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...top,
            for (final w in children) ...[w, SizedBox(height: gap)],
          ],
        );
      }
      final cols = List.generate(n, (_) => <Widget>[]);
      for (var i = 0; i < children.length; i++) {
        cols[i % n].add(children[i]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...top,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final w in cols[i]) ...[w, SizedBox(height: gap)],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    },
  );
}

/// Yan yana, eşit genişlikli bölmeler; dar alanda alt alta. Grafik/kart çiftleri için.
class SideBySide extends StatelessWidget {
  const SideBySide({
    super.key,
    required this.children,
    this.gap = Space.md,
    this.minChildWidth = 420,
  });

  final List<Widget> children;
  final double gap;

  /// Her çocuğa en az bu kadar yer düşmüyorsa alt alta dizilir.
  final double minChildWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final n = children.length;
      final fits = n > 1 && c.maxWidth >= n * minChildWidth + (n - 1) * gap;
      if (!fits) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) SizedBox(height: gap),
              children[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: children[i]),
          ],
        ],
      );
    },
  );
}
