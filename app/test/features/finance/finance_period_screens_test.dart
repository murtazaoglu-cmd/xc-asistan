import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/auth/session.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/finance/data/finance_models.dart';
import 'package:xc_asistan/features/finance/data/finance_providers.dart';

import 'finance_harness.dart';

Finder inCard(String key, Finder f) =>
    find.descendant(of: find.byKey(Key(key)), matching: f);

Future<void> tapText(FinanceHandle h, String text, {int index = 0}) async {
  await h.tester.ensureVisible(find.text(text).at(index));
  await h.settle(2);
  await h.tester.tap(find.text(text).at(index));
  await h.settle();
}

void main() {
  setUp(() => Ist.clock = () => DateTime.utc(2026, 11, 20, 8));
  tearDown(() => Ist.clock = DateTime.now);

  group('Tarih aralığı', () {
    testWidgets('aralık seçici açılır; Vazgeç ay seçicide bırakır', (t) async {
      final h = await pumpFinance(t);
      // Çerçevenin kendi aralık seçicisi Ahem yazı tipiyle dar ekranda taşar; geniş pencere.
      t.view.physicalSize = const Size(2400, 2400);
      await h.settle();
      await t.tap(find.byKey(const Key('pick-range')));
      await h.settle();
      expect(find.text('Tarih aralığı seçin'), findsOneWidget);
      await t.tap(find.byIcon(Icons.close).last);
      await h.settle();
      expect(find.text('Tarih aralığı seçin'), findsNothing);
      expect(find.byKey(const Key('range-chip')), findsNothing);
      expect(find.text('Kasım 2026'), findsOneWidget);
    });

    testWidgets(
      'aralık: özet yalnız aralığı kapsar; zarar etiketi; çip kaldırınca aya döner',
      (t) async {
        final h = await pumpFinance(t);
        // 15-20 Kas: tahsilat 6.000 + 2.500; dükkan 15.000 + işletme 3.200,50 + 850 → zarar.
        h.container
            .read(customPeriodProvider.notifier)
            .setRange(Ist.fromWall(2026, 11, 15), Ist.fromWall(2026, 11, 20));
        await h.settle();
        expect(find.byKey(const Key('range-chip')), findsOneWidget);
        expect(
          find.text('Seçili aralık: 15 Kas – 20 Kas 2026'),
          findsOneWidget,
        );
        expect(inCard('card-revenue', find.text('₺8.500,00')), findsOneWidget);
        expect(inCard('card-profit', find.text('Zarar')), findsOneWidget);
        expect(find.byTooltip('Önceki ay'), findsNothing);
        // Dükkan / İşletme kırılımı satırları.
        expect(inCard('row-shop', find.text('₺15.000,00')), findsOneWidget);
        expect(inCard('row-general', find.text('₺4.050,50')), findsOneWidget);

        // Dar aralık (12 Kas): yalnız ilk tahsilat 4.000, gider yok → Kâr.
        h.container
            .read(customPeriodProvider.notifier)
            .setRange(Ist.fromWall(2026, 11, 12), Ist.fromWall(2026, 11, 12));
        await h.settle();
        expect(inCard('card-revenue', find.text('₺4.000,00')), findsOneWidget);
        expect(inCard('card-profit', find.text('Kâr')), findsOneWidget);

        // Çipin ✕ düğmesi → ay seçici geri gelir.
        await t.tap(find.byTooltip('Aralığı kaldır (aylara dön)'));
        await h.settle();
        expect(find.byKey(const Key('range-chip')), findsNothing);
        expect(find.byTooltip('Önceki ay'), findsOneWidget);
        expect(find.text('Kasım 2026'), findsOneWidget);
      },
    );

    testWidgets('Ödemeler ve Giderler sekmeleri de aralığı kullanır', (
      t,
    ) async {
      final h = await pumpFinance(t);
      h.container
          .read(customPeriodProvider.notifier)
          .setRange(Ist.fromWall(2026, 11, 16), Ist.fromWall(2026, 11, 18));
      await tapText(h, 'Ödemeler');
      expect(
        find.text('1 ödeme'),
        findsOneWidget,
      ); // yalnız 17 Kas "Avans" 6.000
      expect(inCard('payments-total', find.text('₺6.000,00')), findsOneWidget);
      await tapText(h, 'Giderler');
      expect(find.text('Dükkan Giderleri'), findsOneWidget);
    });
  });

  group('Ödemeler: yöntem filtresi ve tüm zamanlar', () {
    testWidgets('Nakit / Havale süzer; "Tüm yöntemler" geri getirir', (
      t,
    ) async {
      final h = await pumpFinance(t);
      await tapText(h, 'Ödemeler');
      expect(find.text('3 ödeme'), findsOneWidget);
      await tapText(h, 'Nakit');
      expect(find.text('1 ödeme'), findsOneWidget);
      expect(inCard('payments-total', find.text('₺6.000,00')), findsOneWidget);
      await tapText(h, 'Havale');
      expect(inCard('payments-total', find.text('₺4.000,00')), findsOneWidget);
      await tapText(h, 'Kredi Kartı');
      expect(inCard('payments-total', find.text('₺2.500,00')), findsOneWidget);
      await tapText(h, 'Tüm yöntemler');
      expect(find.text('3 ödeme'), findsOneWidget);
      // Tüm zamanlar: ay seçiminden bağımsız tüm tahsilat.
      expect(
        inCard('payments-alltime', find.text('₺12.500,00')),
        findsOneWidget,
      );
    });

    testWidgets('yöntem + dönem boşsa süzgeç mesajı', (t) async {
      final h = await pumpFinance(t);
      await tapText(h, 'Ödemeler');
      h.container
          .read(customPeriodProvider.notifier)
          .setRange(Ist.fromWall(2026, 11, 12), Ist.fromWall(2026, 11, 12));
      await h.settle();
      await tapText(h, 'Nakit');
      expect(find.text('Bu süzgeçte ödeme yok'), findsOneWidget);
    });
  });

  group('Kim ne kadar aldı', () {
    Payment p(String id, double tl, String owner, int day) => Payment(
      id: id,
      projectId: 'prj-1',
      amount: Money.fromTl(tl),
      method: 'Nakit',
      paidAt: Ist.fromWall(2026, 11, day, 12),
      ownerId: owner,
      customerName: 'Zeynep',
      projectCode: 'PRJ-1',
    );

    testWidgets('iki sahip: özet kartı adlarla; satıra dokununca süzülür', (
      t,
    ) async {
      final h = await pumpFinance(
        t,
        extraOverrides: [
          paymentsProvider.overrideWith(
            (ref) async => [
              p('1', 1000, 'u-admin', 5),
              p('2', 4000, 'u-personel', 6),
              p('3', 500, 'u-personel', 7),
            ],
          ),
          ownerDirectoryProvider.overrideWithValue(
            const OwnerDirectory(
              selfId: 'u-admin',
              names: {'u-admin': 'Yönetici', 'u-personel': 'Personel'},
            ),
          ),
        ],
      );
      await tapText(h, 'Ödemeler');
      expect(find.byKey(const Key('owner-summary')), findsOneWidget);
      expect(inCard('owner-summary', find.text('Personel')), findsOneWidget);
      expect(inCard('owner-summary', find.text('₺4.500,00')), findsOneWidget);
      expect(
        inCard('owner-summary', find.text('Yönetici (Ben)')),
        findsOneWidget,
      );
      expect(inCard('owner-summary', find.text('₺1.000,00')), findsOneWidget);
      // Başkasının defterindeki kayıtta "Defter: Personel" görünür, kendiminkinde yok.
      expect(find.textContaining('Defter: Personel'), findsNWidgets(2));
      // Süz: Personel
      await t.tap(inCard('owner-summary', find.text('Personel')));
      await h.settle();
      expect(inCard('payments-total', find.text('2 ödeme')), findsOneWidget);
      expect(inCard('payments-total', find.text('₺4.500,00')), findsOneWidget);
      // Yeniden dokun: süzgeç kalkar.
      await t.tap(inCard('owner-summary', find.text('Personel')));
      await h.settle();
      expect(inCard('payments-total', find.text('3 ödeme')), findsOneWidget);
    });

    testWidgets('tek sahip: özet kartı gösterilmez', (t) async {
      final h = await pumpFinance(
        t,
        extraOverrides: [
          paymentsProvider.overrideWith(
            (ref) async => [
              p('1', 1000, 'u-admin', 5),
              p('2', 20, 'u-admin', 6),
            ],
          ),
        ],
      );
      await tapText(h, 'Ödemeler');
      expect(find.byKey(const Key('owner-summary')), findsNothing);
    });
  });

  group('Kayıt sahibi seçici', () {
    List<dynamic> adminOverrides() => [
      capabilitiesProvider.overrideWithValue(
        AppCapabilities.forRole(UserRole.admin),
      ),
      ownerDirectoryProvider.overrideWithValue(
        const OwnerDirectory(
          selfId: 'u-admin',
          names: {'u-admin': 'Yönetici', 'u-personel': 'Personel'},
        ),
      ),
    ];

    testWidgets(
      'admin ödeme formunda seçici görür; Personel seçilince owner_id yazılır',
      (t) async {
        final h = await pumpFinance(
          t,
          initialLocation: '/finance/payments/new?projectId=prj-1',
          extraOverrides: [...adminOverrides().cast()],
        );
        expect(find.byKey(const Key('owner-picker')), findsOneWidget);
        await t.tap(find.byKey(const Key('owner-u-personel')));
        await h.settle();
        await t.enterText(find.byType(TextFormField).first, '100');
        await t.tap(find.text('Kaydet'));
        await h.settle(20);
        final list = await h.container.read(paymentsProvider.future);
        final created = list.firstWhere((e) => e.amount == Money.fromTl(100));
        expect(created.ownerId, 'u-personel');
      },
    );

    testWidgets('seçilmezse kendi defterim: owner_id gönderilmez (sahip ben)', (
      t,
    ) async {
      final h = await pumpFinance(
        t,
        initialLocation: '/finance/payments/new?projectId=prj-1',
        extraOverrides: [...adminOverrides().cast()],
      );
      await t.enterText(find.byType(TextFormField).first, '75');
      await t.tap(find.text('Kaydet'));
      await h.settle(20);
      final list = await h.container.read(paymentsProvider.future);
      expect(
        list.firstWhere((e) => e.amount == Money.fromTl(75)).ownerId,
        'u-admin',
      );
    });

    testWidgets('personel + projesiz gider: aday yok, seçici hiç görünmez', (
      t,
    ) async {
      final h = await pumpFinance(
        t,
        role: UserRole.personel,
        initialLocation: '/finance/expenses/new',
        extraOverrides: [
          capabilitiesProvider.overrideWithValue(
            AppCapabilities.forRole(UserRole.personel),
          ),
          ownerDirectoryProvider.overrideWithValue(
            const OwnerDirectory(
              selfId: 'u-personel',
              names: {'u-personel': 'Personel', 'u-admin': 'Yönetici'},
            ),
          ),
        ],
      );
      expect(h.location, '/finance/expenses/new');
      expect(find.byKey(const Key('owner-picker')), findsNothing);
    });

    testWidgets('admin gider formu: projesiz giderde ekip adayları görünür', (
      t,
    ) async {
      final h = await pumpFinance(
        t,
        initialLocation: '/finance/expenses/new',
        extraOverrides: [...adminOverrides().cast()],
      );
      expect(h.location, '/finance/expenses/new');
      await t.scrollUntilVisible(
        find.byKey(const Key('owner-picker')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('owner-picker')), findsOneWidget);
      expect(find.byKey(const Key('owner-u-personel')), findsOneWidget);
    });
  });
}
