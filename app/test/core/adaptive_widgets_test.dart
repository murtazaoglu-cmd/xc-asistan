// Çekirdek geniş ekran widget'ları: ResponsiveColumns, SideBySide, DataTableView, komut paleti süzgeci.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/router/command_palette.dart';
import 'package:xc_asistan/core/theme/app_theme.dart';
import 'package:xc_asistan/core/ui/ui.dart';

Widget host(Widget child, {double width = 1200}) => MaterialApp(
  theme: AppTheme.light(primary: const Color(0xFF3B82F6)),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(child: child),
      ),
    ),
  ),
);

Widget box(String t) => SizedBox(key: ValueKey(t), height: 40, child: Text(t));

void main() {
  group('ResponsiveColumns', () {
    test('sütun sayısı genişliğe göre', () {
      expect(ResponsiveColumns.columnsFor(500), 1);
      expect(ResponsiveColumns.columnsFor(720), 2);
      expect(ResponsiveColumns.columnsFor(1099), 2);
      expect(ResponsiveColumns.columnsFor(1100), 3);
      expect(ResponsiveColumns.columnsFor(1400, max: 2), 2);
    });

    testWidgets('1200 dp: 3 sütun, okuma sırası soldan sağa', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          ResponsiveColumns(
            fullWidth: [box('tam')],
            children: [
              for (final t in ['a', 'b', 'c', 'd']) box(t),
            ],
          ),
        ),
      );
      double x(String k) => tester.getTopLeft(find.byKey(ValueKey(k))).dx;
      double y(String k) => tester.getTopLeft(find.byKey(ValueKey(k))).dy;
      expect(x('a') < x('b') && x('b') < x('c'), isTrue);
      expect(y('a'), y('b'));
      expect(x('d'), x('a')); // dördüncü: ilk sütunda bir alt satır
      expect(y('d') > y('a'), isTrue);
      expect(y('tam') < y('a'), isTrue);
    });

    testWidgets('dar alanda tek sütun', (tester) async {
      await tester.pumpWidget(
        host(ResponsiveColumns(children: [box('a'), box('b')]), width: 400),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('a'))).dx,
        tester.getTopLeft(find.byKey(const ValueKey('b'))).dx,
      );
    });
  });

  group('SideBySide', () {
    testWidgets('yeterince genişse yan yana, değilse alt alta', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(SideBySide(minChildWidth: 300, children: [box('a'), box('b')])),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('a'))).dy,
        tester.getTopLeft(find.byKey(const ValueKey('b'))).dy,
      );
      await tester.pumpWidget(
        host(
          SideBySide(minChildWidth: 300, children: [box('a'), box('b')]),
          width: 500,
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('b'))).dy >
            tester.getTopLeft(find.byKey(const ValueKey('a'))).dy,
        isTrue,
      );
    });
  });

  group('DataTableView', () {
    final rows = [
      (name: 'Çağla', n: 30),
      (name: 'Ali', n: 10),
      (name: 'Zeynep', n: 20),
      (name: 'Özge', n: 5),
    ];
    final tapped = <String>[];

    Widget table({bool export = false}) => host(
      DataTableView<({String name, int n})>(
        items: rows,
        showExport: export,
        onRowTap: (r) => tapped.add(r.name),
        columns: [
          DataColumnSpec(
            label: 'Ad',
            text: (r) => r.name,
            sortKey: (r) => r.name,
          ),
          DataColumnSpec(
            label: 'Adet',
            numeric: true,
            text: (r) => '${r.n}',
            sortKey: (r) => r.n,
          ),
        ],
      ),
    );

    List<String> order(WidgetTester t) =>
        [
          for (final r in rows)
            if (find.text(r.name).evaluate().isNotEmpty) r.name,
        ]..sort(
          (a, b) => t
              .getTopLeft(find.text(a))
              .dy
              .compareTo(t.getTopLeft(find.text(b)).dy),
        );

    testWidgets(
      'başlığa tıklayınca sıralanır (Türkçe harfler doğru), tekrar tıklayınca tersine',
      (tester) async {
        await tester.pumpWidget(table());
        expect(order(tester), [
          'Çağla',
          'Ali',
          'Zeynep',
          'Özge',
        ]); // verilen sıra
        await tester.tap(find.byKey(const ValueKey('sort-Ad')));
        await tester.pump();
        // Ali, Çağla (c), Özge (o), Zeynep
        expect(order(tester), ['Ali', 'Çağla', 'Özge', 'Zeynep']);
        await tester.tap(find.byKey(const ValueKey('sort-Ad')));
        await tester.pump();
        expect(order(tester), ['Zeynep', 'Özge', 'Çağla', 'Ali']);
        await tester.tap(find.byKey(const ValueKey('sort-Adet')));
        await tester.pump();
        expect(order(tester), ['Özge', 'Ali', 'Zeynep', 'Çağla']);
      },
    );

    testWidgets('satıra tıklama ve klavye (Tab + Enter) satırı açar', (
      tester,
    ) async {
      tapped.clear();
      await tester.pumpWidget(table());
      await tester.tap(find.text('Ali'));
      await tester.pump();
      expect(tapped, ['Ali']);

      // Klavye: Tab ile ilk odaklanabilir öğe (sütun başlığı), sonra satırlar.
      tapped.clear();
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapped, isNotEmpty, reason: 'Enter odaktaki satırı açmalı');
    });

    testWidgets('fare üzerine gelince satır vurgulanır (hover) ve el imleci', (
      tester,
    ) async {
      await tester.pumpWidget(table());
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: Offset.zero);
      await g.moveTo(tester.getCenter(find.text('Ali')));
      await tester.pump();
      final inkwell = tester.widget<InkWell>(
        find.byKey(const ValueKey('row-1')),
      );
      expect(inkwell.hoverColor, isNotNull);
      expect(
        inkwell.mouseCursor ?? SystemMouseCursors.click,
        SystemMouseCursors.click,
      );
    });

    testWidgets(
      'CSV / Yazdır düğmeleri (showExport) görünür; web dışında nazik uyarı',
      (tester) async {
        await tester.pumpWidget(table(export: true));
        expect(find.byKey(const ValueKey('table-csv')), findsOneWidget);
        expect(find.text('4 kayıt'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('table-csv')));
        await tester.pump();
        expect(find.textContaining('indirilemiyor'), findsOneWidget);
      },
    );

    testWidgets('kısaltılan hücrede ipucu (tooltip) metni tam içerir', (
      tester,
    ) async {
      await tester.pumpWidget(table());
      expect(find.byTooltip('Çağla'), findsOneWidget);
    });
  });

  group('Komut paleti', () {
    final entries = [
      PaletteEntry(
        id: 'a',
        label: 'Müşteriler',
        icon: Icons.group,
        onSelect: () {},
      ),
      PaletteEntry(
        id: 'b',
        label: 'Fatura / KDV',
        icon: Icons.receipt,
        onSelect: () {},
        keywords: 'vergi',
      ),
      PaletteEntry(
        id: 'c',
        label: 'Işık ayarı',
        icon: Icons.light_mode,
        onSelect: () {},
      ),
    ];
    test('Türkçe harf duyarsız süzgeç', () {
      expect(filterPalette(entries, '').length, 3);
      expect(filterPalette(entries, 'musteri').single.id, 'a');
      expect(filterPalette(entries, 'MÜŞTERİ').single.id, 'a');
      expect(filterPalette(entries, 'vergi').single.id, 'b');
      expect(filterPalette(entries, 'isik').single.id, 'c');
      expect(filterPalette(entries, 'yok'), isEmpty);
    });
  });
}
