import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/features/stock/data/stock_models.dart';
import 'package:xc_asistan/features/stock/data/stock_repository.dart';
import 'package:xc_asistan/features/stock/presentation/stock_form_screen.dart';
import 'package:xc_asistan/features/stock/presentation/stock_screen.dart';

import 'harness.dart';
import 'stock_data_test.dart' show FakeStockRepo, mat;

FakeStockRepo repo() => FakeStockRepo([
  StockItem.fromJson(mat('m1', 'Boya', 4, 5)),
  StockItem.fromJson(mat('m2', 'Vida seti', 40, 10)),
  StockItem.fromJson(mat('m3', 'Conta', 0, 20)),
]);

void main() {
  late Duration saved;
  setUp(() {
    saved = StockListNotifier.debounce;
    StockListNotifier.debounce = const Duration(milliseconds: 30);
  });
  tearDown(() => StockListNotifier.debounce = saved);

  testWidgets('liste: düşük stok ve tükendi vurgusu (renk + ikon + yazı)', (
    t,
  ) async {
    await pumpScreen(
      t,
      const StockScreen(),
      overrides: [stockRepositoryProvider.overrideWithValue(repo())],
    );
    await settle(t);
    expect(find.text('Düşük stok'), findsWidgets); // chip + süzgeç
    expect(find.text('Tükendi'), findsOneWidget);
    expect(find.text('Düşük stok (2)'), findsOneWidget);
    expect(find.text('Tümü (3)'), findsOneWidget);
    // Düşük olanlar önce: Boya/Conta, sonra Vida seti.
    final yBoya = t.getTopLeft(find.text('Boya')).dy;
    final yVida = t.getTopLeft(find.text('Vida seti')).dy;
    expect(yBoya < yVida, isTrue);
    expect(find.text('Stok'), findsWidgets); // sözlük başlığı
  });

  testWidgets('tek dokunuşla artır: ekranda hemen, sunucuya tek yazma', (
    t,
  ) async {
    final r = repo();
    await pumpScreen(
      t,
      const StockScreen(),
      overrides: [stockRepositoryProvider.overrideWithValue(r)],
    );
    await settle(t);
    final plus = find.byTooltip('Boya artır');
    await t.tap(plus);
    await t.tap(plus);
    await t.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('qty-m1')),
        matching: find.text('6'),
      ),
      findsOneWidget,
    );
    await t.pump(const Duration(milliseconds: 80));
    await t.pump();
    expect(r.writes, [('m1', 6.0)]);
    // 6 > asgari 5: artık düşük değil
    await settle(t);
    expect(find.text('Düşük stok (1)'), findsOneWidget);
  });

  testWidgets('miktar 0 iken azalt düğmesi pasif', (t) async {
    await pumpScreen(
      t,
      const StockScreen(),
      overrides: [stockRepositoryProvider.overrideWithValue(repo())],
    );
    await settle(t);
    final btn = t.widget<IconButton>(
      find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Conta azalt',
      ),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('dokunma hedefleri en az 48 dp', (t) async {
    await pumpScreen(
      t,
      const StockScreen(),
      overrides: [stockRepositoryProvider.overrideWithValue(repo())],
    );
    await settle(t);
    for (final tip in ['Boya artır', 'Boya azalt']) {
      final s = t.getSize(find.byTooltip(tip));
      expect(s.width >= 48 && s.height >= 48, isTrue, reason: tip);
    }
    final q = t.getSize(find.byKey(const Key('qty-m1')));
    expect(q.height >= 48, isTrue);
  });

  testWidgets('değer girişi: virgüllü sayı hemen yazılır', (t) async {
    final r = repo();
    await pumpScreen(
      t,
      const StockScreen(),
      overrides: [stockRepositoryProvider.overrideWithValue(r)],
    );
    await settle(t);
    await t.tap(find.byKey(const Key('qty-m1')));
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(find.byType(TextFormField), '12,5');
    await t.tap(find.text('Kaydet'));
    await settle(t);
    expect(r.writes, [('m1', 12.5)]);
  });

  testWidgets('değer girişi: negatif/geçersiz değer reddedilir', (t) async {
    final r = repo();
    await pumpScreen(
      t,
      const StockScreen(),
      overrides: [stockRepositoryProvider.overrideWithValue(r)],
    );
    await settle(t);
    await t.tap(find.byKey(const Key('qty-m1')));
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(find.byType(TextFormField), '');
    await t.tap(find.text('Kaydet'));
    await t.pump();
    expect(find.text('Miktar girin.'), findsOneWidget);
    expect(r.writes, isEmpty);
  });

  testWidgets('yalnız düşük stok süzgeci ve arama', (t) async {
    await pumpScreen(
      t,
      const StockScreen(),
      overrides: [stockRepositoryProvider.overrideWithValue(repo())],
    );
    await settle(t);
    await t.tap(find.text('Düşük stok (2)'));
    await settle(t);
    expect(find.text('Vida seti'), findsNothing);
    expect(find.text('Boya'), findsOneWidget);
    await t.tap(find.text('Tümü (3)'));
    await settle(t);
    await t.enterText(find.byType(TextField).first, 'vida');
    await settle(t);
    expect(find.text('Boya'), findsNothing);
    expect(find.text('Vida seti'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'zzz');
    await settle(t);
    expect(find.text('Sonuç bulunamadı'), findsOneWidget);
  });

  testWidgets('boş stok: davet', (t) async {
    await pumpScreen(
      t,
      const StockScreen(),
      overrides: [stockRepositoryProvider.overrideWithValue(FakeStockRepo([]))],
    );
    await settle(t);
    expect(find.text('Henüz malzeme yok'), findsOneWidget);
  });

  testWidgets('rol görünürlüğü: personel/saha göremez, A/M/O görür', (t) async {
    for (final role in [UserRole.personel, UserRole.saha]) {
      await pumpScreen(
        t,
        const StockScreen(),
        role: role,
        overrides: [stockRepositoryProvider.overrideWithValue(repo())],
      );
      await settle(t);
      expect(
        find.text('Bu bölüm için yetkiniz yok'),
        findsOneWidget,
        reason: role.api,
      );
    }
    for (final role in [UserRole.admin, UserRole.muhasebe, UserRole.ortak]) {
      await pumpScreen(
        t,
        const StockScreen(),
        role: role,
        overrides: [stockRepositoryProvider.overrideWithValue(repo())],
      );
      await settle(t);
      expect(find.text('Boya'), findsOneWidget, reason: role.api);
    }
  });

  group('Malzeme formu', () {
    testWidgets('boş ad ve eksik miktar doğrulanır', (t) async {
      final r = repo();
      await pumpScreen(
        t,
        const StockFormScreen(),
        overrides: [stockRepositoryProvider.overrideWithValue(r)],
      );
      await t.enterText(find.byKey(const Key('field-qty')), '');
      await t.tap(find.text('Malzeme ekle'));
      await t.pump();
      expect(find.text('Malzeme adı girin.'), findsOneWidget);
      expect(find.text('Miktar girin.'), findsOneWidget);
      expect(r.writes, isEmpty);
      // eksi işareti klavyeden de girilemez
      await t.enterText(find.byKey(const Key('field-qty')), '-3');
      final tf = t.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('field-qty')),
          matching: find.byType(TextField),
        ),
      );
      expect(tf.controller!.text, '3');
    });

    testWidgets('düzenleme: mevcut değerler dolu, sil düğmesi var', (t) async {
      await pumpScreen(
        t,
        const StockFormScreen(id: 'm1'),
        overrides: [stockRepositoryProvider.overrideWithValue(repo())],
      );
      await settle(t);
      expect(find.widgetWithText(TextFormField, 'Boya'), findsOneWidget);
      expect(find.byTooltip('Sil'), findsOneWidget);
      expect(find.text('Değişiklikleri kaydet'), findsNothing);
    });
  });
}
