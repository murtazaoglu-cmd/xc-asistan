import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/features/finance/data/finance_access.dart';
import 'package:xc_asistan/features/finance/data/finance_providers.dart';
import 'package:xc_asistan/features/finance/presentation/finance_screen.dart';

import '../../helpers/fakes.dart';
import 'finance_harness.dart';

Finder inCard(String key, Finder f) =>
    find.descendant(of: find.byKey(Key(key)), matching: f);

Finder get mainScrollable => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> tapText(FinanceHandle h, String text, {int index = 0}) async {
  await h.tester.ensureVisible(find.text(text).at(index));
  await h.settle(2);
  await h.tester.tap(find.text(text).at(index));
  await h.settle();
}

Future<void> scrollTo(FinanceHandle h, Finder f) async {
  await h.tester.scrollUntilVisible(f, 250, scrollable: mainScrollable);
  await h.settle(3);
}

void main() {
  setUp(() => Ist.clock = () => DateTime.utc(2026, 11, 20, 8));
  tearDown(() => Ist.clock = DateTime.now);

  group('Para özeti (admin)', () {
    testWidgets(
      'üstte hızlı butonlar, ay seçici, Gelir/Gider/Kâr ve Kişisel ayrı',
      (tester) async {
        final h = await pumpFinance(
          tester,
          role: UserRole.admin,
          initialLocation: '/finance',
        );
        expect(h.location, '/finance');
        final addPay = find.byKey(const Key('quick-add-payment'));
        final addExp = find.byKey(const Key('quick-add-expense'));
        expect(addPay, findsOneWidget);
        expect(addExp, findsOneWidget);
        // Sayfanın ÜSTÜNDE: sekmelerden ve kartlardan yukarıda, dokunma ≥ 48.
        final tabY = tester.getTopLeft(find.text('Ödemeler').first).dy;
        expect(tester.getTopLeft(addPay).dy, lessThan(tabY));
        expect(tester.getSize(addPay).height, greaterThanOrEqualTo(48));
        expect(find.text('Kasım 2026'), findsOneWidget);
        expect(find.byTooltip('Önceki ay'), findsOneWidget);

        // Demo: tahsilat 12.500; işletme gideri 15.000 + 3.200,50 + 850; ev gideri 12.000.
        expect(inCard('card-revenue', find.text('₺12.500,00')), findsOneWidget);
        expect(inCard('card-expense', find.text('₺19.050,50')), findsOneWidget);
        expect(inCard('card-profit', find.text('−₺6.550,50')), findsOneWidget);
        // Ev gideri kâra katılmaz: ayrı "Kişisel" satırı.
        expect(inCard('row-personal', find.text('₺12.000,00')), findsOneWidget);
        expect(find.text('İşletme kârına dahil değil'), findsOneWidget);
      },
    );

    testWidgets('ay seçici: önceki aya geçilir, gelecek aya gidilmez', (
      tester,
    ) async {
      final h = await pumpFinance(
        tester,
        role: UserRole.admin,
        initialLocation: '/finance',
      );
      await h.tester.tap(find.byTooltip('Önceki ay'));
      await h.settle();
      expect(find.text('Ekim 2026'), findsOneWidget);
      expect(inCard('card-revenue', find.text('₺0,00')), findsOneWidget);
      await h.tester.tap(find.byTooltip('Sonraki ay'));
      await h.settle();
      expect(find.text('Kasım 2026'), findsOneWidget);
      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(next.onPressed, isNull);
    });

    testWidgets('grafik en çok 6 ay: gösterge üstte, tablo seçeneği var', (
      tester,
    ) async {
      final h = await pumpFinance(
        tester,
        role: UserRole.admin,
        initialLocation: '/finance',
      );
      expect(find.text('Son 6 ay'), findsOneWidget);
      expect(find.text('Gelir'), findsWidgets);
      expect(find.text('Gider (işletme)'), findsOneWidget);
      await scrollTo(h, find.text('Tablo olarak göster'));
      expect(find.text('Tablo olarak göster'), findsOneWidget);
    });

    testWidgets('alacaklar: kalan bakiye, vadesi geçen vurgulu, ham UUID yok', (
      tester,
    ) async {
      final h = await pumpFinance(
        tester,
        role: UserRole.admin,
        initialLocation: '/finance',
      );
      await scrollTo(h, find.text('Alacaklar'));
      // prj-1: Zeynep Arslan, 8.500 − 4.000, bitiş 3 gün önce → vadesi geçmiş.
      expect(find.text('PRJ-501 · Zeynep Arslan'), findsOneWidget);
      expect(find.textContaining('Vadesi geçti'), findsWidgets);
      expect(find.textContaining('prj-'), findsNothing);
      // Tamamlanan ve tamamen ödenen Burak Aydın alacak değildir.
      expect(find.textContaining('Burak Aydın'), findsNothing);
    });

    testWidgets(
      "WhatsApp'ta hatırlat: hazır nazik metin wa.me/uygulama ile açılır",
      (tester) async {
        final h = await pumpFinance(
          tester,
          role: UserRole.admin,
          initialLocation: '/finance',
        );
        await scrollTo(h, find.text('PRJ-501 · Zeynep Arslan'));
        await tapText(h, 'PRJ-501 · Zeynep Arslan');
        expect(find.text("WhatsApp'ta hatırlat"), findsOneWidget);
        expect(
          find.text('Vade ve ödeme sözü bilgisi burada gösterilecek.'),
          findsOneWidget,
        ); // PaymentScheduleSection yer tutucusu
        await tapText(h, "WhatsApp'ta hatırlat");
        final launcher = h.launcher;
        expect(launcher.opened, isNotEmpty);
        final uri = launcher.opened.last;
        expect(uri.toString(), contains('905321112231'));
        expect(Uri.decodeComponent(uri.toString()), contains('kalan bakiye'));
        expect(Uri.decodeComponent(uri.toString()), contains('teşekkür'));
      },
    );

    testWidgets('Ödemeler sekmesi: proje kodu + müşteri adı, UUID yok', (
      tester,
    ) async {
      final h = await pumpFinance(
        tester,
        role: UserRole.admin,
        initialLocation: '/finance',
      );
      await tapText(h, 'Ödemeler');
      expect(find.text('PRJ-501 · Zeynep Arslan'), findsOneWidget);
      expect(find.text('PRJ-502 · Ahmet Şahin'), findsOneWidget);
      expect(find.textContaining('prj-'), findsNothing);
      expect(find.textContaining('pay-'), findsNothing);
      expect(inCard('payments-total', find.text('₺12.500,00')), findsOneWidget);
    });

    testWidgets('Giderler sekmesi: Ev / Dükkan / İşletme toplamı ayrı', (
      tester,
    ) async {
      final h = await pumpFinance(
        tester,
        role: UserRole.admin,
        initialLocation: '/finance',
      );
      await tapText(h, 'Giderler');
      // Dükkan 15.000 + İşletme (genel) 3.200,50 + 850 = 4.050,50; Ev 12.000.
      expect(
        inCard('expenses-totals', find.text('₺15.000,00')),
        findsOneWidget,
      );
      expect(inCard('expenses-totals', find.text('₺4.050,50')), findsOneWidget);
      expect(
        inCard('expenses-totals', find.text('₺12.000,00')),
        findsOneWidget,
      );
      expect(find.text('Ev Giderleri (kâra dahil değil)'), findsOneWidget);
      expect(find.text('Dükkan Giderleri'), findsOneWidget);
      expect(find.text('İşletme Giderleri'), findsOneWidget);
      // Süzgeç: Ev → yalnız ev gideri
      await h.tester.tap(find.widgetWithText(ChoiceChip, 'Ev'));
      await h.settle();
      expect(
        find.textContaining('Ev kirası'),
        findsNothing,
      ); // demo: "Ev Kirası"
      expect(find.text('Ev Kirası'), findsOneWidget);
      expect(find.text('Dükkan Kirası'), findsNothing);
    });
  });

  group('Rol görünürlüğü', () {
    testWidgets(
      'saha yetkisiyle ekran açılırsa finans verisi yok, yetki mesajı var',
      (tester) async {
        final overrides = await baseOverrides();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...overrides,
              financeAccessProvider.overrideWithValue(
                const FinanceAccess(UserRole.saha),
              ),
            ],
            child: const MaterialApp(home: FinanceScreen()),
          ),
        );
        await tester.pump();
        expect(find.text('Bu bölüm için yetkiniz yok'), findsOneWidget);
        expect(find.byKey(const Key('quick-add-payment')), findsNothing);
        expect(find.text('Ödemeler'), findsNothing);
      },
    );

    testWidgets('personel: kısıtlı (Sabit giderler ve Ev yok)', (tester) async {
      final h = await pumpFinance(
        tester,
        role: UserRole.personel,
        initialLocation: '/finance',
      );
      expect(h.location, '/finance');
      expect(find.text('Sabit giderler'), findsNothing);
      expect(find.text('Özet'), findsOneWidget);
      expect(find.byKey(const Key('row-personal')), findsNothing);
    });

    testWidgets('admin: Sabit giderler sekmesi var', (tester) async {
      final h = await pumpFinance(
        tester,
        role: UserRole.admin,
        initialLocation: '/finance',
      );
      expect(find.text('Sabit giderler'), findsOneWidget);
      await tapText(h, 'Sabit giderler');
      expect(find.text('Bu ay uygula'), findsWidgets);
    });
  });

  group('Sabit gider uygula', () {
    testWidgets('ilk uygulama eklenir; ikinci kez 409 nazik mesaj gösterir', (
      tester,
    ) async {
      final h = await pumpFinance(
        tester,
        role: UserRole.admin,
        initialLocation: '/finance',
      );
      await tapText(h, 'Sabit giderler');
      await h.tester.tap(find.text('Bu ay uygula').first);
      await h.settle();
      expect(find.textContaining('bu aya eklendi'), findsOneWidget);
      await h.tester.tap(find.text('Bu ay uygula').first);
      await h.settle();
      expect(find.textContaining('Bu ay zaten eklenmiş'), findsOneWidget);
      expect(find.textContaining('Sunucu'), findsNothing);
    });
  });

  group('Ödeme formu', () {
    Future<FinanceHandle> openForm(WidgetTester t) async {
      final h = await pumpFinance(t, role: UserRole.admin);
      await h.tester.tap(find.byKey(const Key('quick-add-payment')));
      await h.settle();
      return h;
    }

    testWidgets('boş kayıt: tutar ve proje hatası; ham UUID yok', (
      tester,
    ) async {
      final h = await openForm(tester);
      expect(find.text('Ödeme ekle'), findsWidgets);
      await h.tester.tap(find.text('Kaydet'));
      await h.settle();
      expect(find.text('Tutarı girin.'), findsOneWidget);
      expect(find.text('Bir proje seçin.'), findsOneWidget);
      expect(find.textContaining('prj-'), findsNothing);
    });

    testWidgets(
      'negatif işareti yazılamaz; sıfır ve geçersiz tutar engellenir',
      (tester) async {
        final h = await openForm(tester);
        final field = find.byType(TextFormField).first;
        await h.tester.enterText(field, '-50');
        await h.settle(2);
        final text = tester.widget<TextFormField>(field).controller!.text;
        expect(text.contains('-'), isFalse);
        await h.tester.enterText(field, '0');
        await h.tester.tap(find.text('Kaydet'));
        await h.settle();
        expect(find.text('Tutar sıfırdan büyük olmalı.'), findsOneWidget);
      },
    );

    testWidgets(
      'proje seç (aramalı, kod + müşteri), hızlı tutar, kaydet → özete yansır',
      (tester) async {
        final h = await openForm(tester);
        await h.tester.tap(find.text('Proje seçin').first);
        await h.settle();
        expect(find.text('PRJ-502 · Ahmet Şahin'), findsOneWidget);
        expect(find.textContaining('prj-'), findsNothing);
        // Arama
        await h.tester.enterText(
          find.widgetWithText(TextField, 'Proje kodu veya müşteri adı ara'),
          'Ahmet',
        );
        await h.tester.pump(const Duration(milliseconds: 400));
        await h.settle();
        expect(find.text('PRJ-501 · Zeynep Arslan'), findsNothing);
        await h.tester.tap(find.text('PRJ-502 · Ahmet Şahin'));
        await h.settle();
        expect(find.text('PRJ-502 · Ahmet Şahin'), findsOneWidget);
        // Ahmet Şahin: 26.000 − 6.000 = 20.000 kalan → "Kalanın tamamı"
        expect(find.textContaining('Kalanın tamamı'), findsOneWidget);
        await h.tester.tap(find.text('%25'));
        await h.settle();
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).first)
              .controller!
              .text,
          '5.000,00',
        );
        await h.tester.tap(find.text('Nakit'));
        await h.tester.tap(find.text('Kaydet'));
        await h.settle(20);
        expect(find.textContaining('₺5.000 tahsilat eklendi'), findsOneWidget);
        expect(find.text('Geri al'), findsOneWidget);
        // Özet güncellendi: 12.500 + 5.000
        expect(h.location, '/finance');
        expect(inCard('card-revenue', find.text('₺17.500,00')), findsOneWidget);
      },
    );

    testWidgets('klavye açıkken Kaydet görünür ve form kaydırılabilir', (
      tester,
    ) async {
      final h = await openForm(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 1200);
      addTearDown(tester.view.resetViewInsets);
      await h.settle(4);
      final save = find.text('Kaydet');
      expect(save, findsOneWidget);
      final viewH =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final kbTop = viewH - 1200 / tester.view.devicePixelRatio;
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(kbTop + 0.5));
      // Form her zaman kaydırılabilir.
      final lv = tester.widget<ListView>(find.byType(ListView).first);
      expect(lv.physics, isA<AlwaysScrollableScrollPhysics>());
    });

    testWidgets('kalandan fazla tutar uyarı gösterir ve onay ister', (
      tester,
    ) async {
      final h = await pumpFinance(
        tester,
        role: UserRole.admin,
        initialLocation: '/finance/payments/new?projectId=prj-1',
      );
      expect(h.location, contains('/finance/payments/new'));
      expect(find.text('PRJ-501 · Zeynep Arslan'), findsOneWidget);
      await h.tester.enterText(find.byType(TextFormField).first, '9000');
      await h.settle(3);
      expect(find.textContaining('kalan bakiyeden'), findsOneWidget);
      await h.tester.tap(find.text('Kaydet'));
      await h.settle();
      expect(find.text('Kalandan fazla'), findsOneWidget);
      await h.tester.tap(find.text('Vazgeç').last);
      await h.settle();
      expect(find.text('Kalandan fazla'), findsNothing);
    });
  });

  group('Gider formu', () {
    testWidgets('personel proje bağsız (genel) gider kaydedemez', (
      tester,
    ) async {
      final h = await pumpFinance(
        tester,
        role: UserRole.personel,
        initialLocation: '/finance/expenses/new',
      );
      expect(find.text('Gider ekle'), findsWidgets);
      await h.tester.enterText(find.byType(TextFormField).first, '100');
      await h.tester.enterText(
        find.widgetWithText(TextFormField, 'Kategori (seçin ya da yazın)'),
        'Yakıt',
      );
      await h.tester.tap(find.text('Kaydet'));
      await h.settle();
      expect(
        find.text(
          'Genel gider ekleme yetkiniz yok. Gideri bir projeye bağlayın.',
        ),
        findsWidgets,
      );
      // Kişisel kapsam personele sunulmaz.
      expect(find.widgetWithText(ChoiceChip, 'Ev'), findsNothing);
    });

    testWidgets('admin: kapsam Ev/Dükkan/İşletme; ev uyarısı; kayıt başarılı', (
      tester,
    ) async {
      final h = await pumpFinance(
        tester,
        role: UserRole.admin,
        initialLocation: '/finance/expenses/new',
      );
      final scrollable = find.byType(Scrollable).first;
      await h.tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'Ev'),
        200,
        scrollable: scrollable,
      );
      await h.settle(3);
      expect(find.widgetWithText(ChoiceChip, 'Ev'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Dükkan'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'İşletme'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Kişisel'), findsNothing);
      await h.tester.tap(find.widgetWithText(ChoiceChip, 'Ev'));
      await h.settle(3);
      expect(
        find.textContaining('işletme kârına dahil edilmez'),
        findsOneWidget,
      );
      await h.tester.drag(scrollable, const Offset(0, 3000));
      await h.settle(3);
      await h.tester.enterText(find.byType(TextFormField).first, '250,75');
      await h.tester.tap(find.widgetWithText(ChoiceChip, 'Market'));
      await h.settle(3);
      await h.tester.tap(find.text('Kaydet'));
      await h.settle(20);
      expect(h.location, '/finance');
      expect(find.textContaining('₺250,75 gider eklendi (Ev)'), findsOneWidget);
      // Ev gideri kâra girmedi, Ev Giderleri satırına girdi: 12.000 + 250,75.
      expect(inCard('row-personal', find.text('₺12.250,75')), findsOneWidget);
      expect(inCard('card-expense', find.text('₺19.050,50')), findsOneWidget);
    });
  });
}
