import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/theme/app_theme.dart';
import 'package:xc_asistan/core/ui/ui.dart';
import 'package:xc_asistan/core/util/money.dart';

import '../helpers/fakes.dart';

Future<void> pumpUi(
  WidgetTester tester,
  Widget child, {
  FakeLinkLauncher? launcher,
  Stream<bool>? connectivity,
  bool scaffold = true,
}) async {
  final overrides = await baseOverrides(
    launcher: launcher,
    connectivity: connectivity,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: scaffold ? Scaffold(body: child) : child,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('MoneyText', () {
    testWidgets('TL biçimi, negatif işareti', (t) async {
      await pumpUi(
        t,
        Column(
          children: [
            MoneyText(Money.fromTl(12450)),
            MoneyText.json('1250.5'),
            MoneyText(Money.fromTl(-1250), colorizeNegative: true),
            MoneyText(Money.fromTl(100), hideZeroKurus: true),
          ],
        ),
      );
      expect(find.text('₺12.450,00'), findsOneWidget);
      expect(find.text('₺1.250,50'), findsOneWidget);
      expect(find.text('−₺1.250,00'), findsOneWidget);
      expect(find.text('₺100'), findsOneWidget);
    });
  });

  group('DateText', () {
    testWidgets('İstanbul saatine çevirir; boşsa yer tutucu', (t) async {
      final d = DateTime.utc(2026, 11, 20, 11, 30);
      await pumpUi(
        t,
        Column(
          children: [
            DateText(d),
            DateText(d, mode: DateTextMode.time),
            DateText(d, mode: DateTextMode.dateTime),
            const DateText(null),
            const DateText(null, placeholder: 'Belirsiz'),
          ],
        ),
      );
      expect(find.text('20 Kas 2026'), findsOneWidget);
      expect(find.text('14:30'), findsOneWidget);
      expect(find.text('20 Kas 2026, 14:30'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
      expect(find.text('Belirsiz'), findsOneWidget);
    });
  });

  group('StatusChip', () {
    testWidgets(
      'sözleşme durumları Türkçe etiket gösterir; bilinmeyen çökmez',
      (t) async {
        await pumpUi(
          t,
          Wrap(
            children: [
              StatusChip.offer('Yeni'),
              StatusChip.offer('İncelendi'),
              StatusChip.offer('bilinmeyen_durum'),
              StatusChip.offer(null),
              StatusChip.appointment('beklemede'),
              StatusChip.send('gonderildi'),
              StatusChip.send('???'),
              StatusChip.task('xyz'),
              StatusChip.stage('xyz'),
            ],
          ),
        );
        expect(find.text('Yeni'), findsOneWidget);
        expect(find.text('İncelendi'), findsOneWidget);
        expect(find.text('Gönderildi'), findsOneWidget);
        expect(t.takeException(), isNull); // bilinmeyen değerler çökertmez
      },
    );
  });

  group('EmptyState / ErrorState / Skeleton / AsyncValueView', () {
    testWidgets('EmptyState eylem düğmesi çalışır', (t) async {
      var n = 0;
      await pumpUi(
        t,
        EmptyState(
          title: 'Randevu yok',
          message: 'Henüz eklenmedi',
          actionLabel: 'İlk randevuyu ekle',
          onAction: () => n++,
        ),
      );
      expect(find.text('Randevu yok'), findsOneWidget);
      await t.tap(find.text('İlk randevuyu ekle'));
      expect(n, 1);
    });

    testWidgets('ErrorState: ağ hatası mesajı + Tekrar dene', (t) async {
      var n = 0;
      await pumpUi(
        t,
        ErrorState(
          error: const AppException(
            AppErrorCode.network,
            'İnternet bağlantısı yok.',
          ),
          onRetry: () => n++,
        ),
      );
      expect(find.text('Tekrar dene'), findsOneWidget);
      await t.tap(find.text('Tekrar dene'));
      expect(n, 1);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('AsyncValueView: yükleniyor / hata / boş / veri', (t) async {
      Widget view(AsyncValue<List<int>> v) => AsyncValueView<List<int>>(
        value: v,
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(title: 'Boş'),
        onRetry: () {},
        data: (l) => Text('n=${l.length}'),
      );
      await pumpUi(t, view(const AsyncLoading()));
      expect(find.byType(SkeletonList), findsOneWidget);
      await pumpUi(
        t,
        view(
          AsyncError(
            const AppException(
              AppErrorCode.network,
              'İnternet bağlantısı yok.',
            ),
            StackTrace.empty,
          ),
        ),
      );
      expect(find.text('Tekrar dene'), findsOneWidget);
      await pumpUi(t, view(const AsyncData([])));
      expect(find.text('Boş'), findsOneWidget);
      await pumpUi(t, view(const AsyncData([1, 2])));
      expect(find.text('n=2'), findsOneWidget);
    });
  });

  group('OfflineBanner', () {
    testWidgets('çevrimdışıyken görünür, çevrimiçiyken gizli', (t) async {
      await pumpUi(t, const OfflineBanner(), connectivity: Stream.value(false));
      await t.pump();
      expect(find.textContaining('İnternet yok'), findsOneWidget);
      await pumpUi(t, const OfflineBanner(), connectivity: Stream.value(true));
      await t.pump();
      expect(find.textContaining('İnternet yok'), findsNothing);
    });
  });

  group('PhoneActions / AddressActions', () {
    testWidgets('Ara ve WhatsApp doğru URI açar', (t) async {
      final l = FakeLinkLauncher();
      await pumpUi(
        t,
        const PhoneActionButtons(phone: '0532 111 22 33', name: 'Ayşe'),
        launcher: l,
      );
      await t.tap(find.text('Ara'));
      await t.pump();
      expect(l.opened.first.toString(), 'tel:+905321112233');
      await t.tap(find.text('WhatsApp'));
      await t.pump();
      expect(l.opened.length, 2);
      expect(l.opened.last.toString(), contains('905321112233'));
    });

    testWidgets('telefon yoksa hiçbir şey çizmez; dar alanda taşmaz', (
      t,
    ) async {
      await pumpUi(t, const PhoneActionButtons(phone: ' '));
      expect(find.byType(OutlinedButton), findsNothing);
      await pumpUi(
        t,
        const SizedBox(
          width: 200,
          child: PhoneActionButtons(phone: '05321112233'),
        ),
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('adres dokununca yol tarifi açar; boşsa gizli', (t) async {
      final l = FakeLinkLauncher();
      await pumpUi(
        t,
        const AddressActions(address: 'Atatürk Cd. 5, Kadıköy'),
        launcher: l,
      );
      await t.tap(find.textContaining('Atatürk Cd.'));
      await t.pump();
      expect(l.opened, hasLength(1));
      await pumpUi(t, const AddressActions(address: '  '));
      expect(find.byIcon(Icons.place_outlined), findsNothing);
    });
  });

  group('BottomSaveBar', () {
    testWidgets('çalışır, yüklerken pasif', (t) async {
      var n = 0;
      await pumpUi(t, BottomSaveBar(onSave: () => n++, onCancel: () {}));
      await t.tap(find.text('Kaydet'));
      expect(n, 1);
      await pumpUi(t, BottomSaveBar(onSave: () => n++, loading: true));
      await t.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(n, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
      'klavye açıkken (viewInsets) AppScaffold.bottomBar görünür kalır',
      (t) async {
        t.view.physicalSize = const Size(1080, 2000);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        t.view.viewInsets = const FakeViewPadding(bottom: 900);
        addTearDown(t.view.resetViewInsets);
        await pumpUi(
          t,
          AppScaffold(
            title: 'Form',
            body: const Center(child: TextField()),
            bottomBar: BottomSaveBar(onSave: () {}),
          ),
          scaffold: false,
        );
        final bar = t.getRect(find.text('Kaydet'));
        final visibleBottom = (2000 - 900) / 3;
        expect(bar.bottom, lessThanOrEqualTo(visibleBottom));
        expect(bar.top, greaterThan(0));
      },
    );
  });

  group('ConfirmDialog / UndoSnackbar / PullToRefresh', () {
    testWidgets('ConfirmDialog onay/vazgeç', (t) async {
      late BuildContext ctx;
      await pumpUi(
        t,
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      );
      var f = ConfirmDialog.show(
        ctx,
        title: 'Silinsin mi?',
        destructive: true,
        confirmLabel: 'Sil',
      );
      await t.pumpAndSettle();
      expect(find.text('Silinsin mi?'), findsOneWidget);
      await t.tap(find.text('Sil'));
      await t.pumpAndSettle();
      expect(await f, isTrue);
      f = ConfirmDialog.show(ctx, title: 'Silinsin mi?');
      await t.pumpAndSettle();
      await t.tap(find.text('Vazgeç'));
      await t.pumpAndSettle();
      expect(await f, isFalse);
    });

    testWidgets('UndoSnackbar.show: Geri al çağrılır', (t) async {
      late BuildContext ctx;
      var undone = 0;
      await pumpUi(
        t,
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      );
      UndoSnackbar.show(ctx, message: 'Tamamlandı', onUndo: () => undone++);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Geri al'));
      await t.pump();
      expect(undone, 1);
    });

    testWidgets(
      'UndoSnackbar.deferred: geri alınmazsa commit, alınırsa commit YOK',
      (t) async {
        late BuildContext ctx;
        var commits = 0, undone = 0;
        await pumpUi(
          t,
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        );
        // süre dolsun → commit
        UndoSnackbar.deferred(
          ctx,
          message: 'Silindi',
          duration: const Duration(seconds: 2),
          onCommit: () async => commits++,
          onUndo: () => undone++,
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(commits, 0);
        await t.pump(const Duration(seconds: 3));
        await t.pump(const Duration(seconds: 1));
        expect(commits, 1);
        expect(undone, 0);
        // geri al → commit yok
        UndoSnackbar.deferred(
          ctx,
          message: 'Silindi 2',
          onCommit: () async => commits++,
          onUndo: () => undone++,
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await t.tap(find.text('Geri al'));
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        expect(commits, 1);
        expect(undone, 1);
      },
    );

    testWidgets('PullToRefresh.fill: boş içerikte de çekilince yeniler', (
      t,
    ) async {
      var n = 0;
      await pumpUi(
        t,
        PullToRefresh.fill(
          onRefresh: () async => n++,
          child: const EmptyState(title: 'Boş'),
        ),
      );
      await t.fling(find.text('Boş'), const Offset(0, 400), 1000);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(n, 1);
    });
  });

  group('FeaturePlaceholder / SectionCard', () {
    testWidgets('yer tutucu başlık ve açıklamayı gösterir', (t) async {
      await pumpUi(
        t,
        const FeaturePlaceholder(
          title: 'Stok',
          icon: Icons.inventory_2,
          description: 'Hazırlanıyor',
          routeInfo: 'id: 5',
        ),
        scaffold: false,
      );
      expect(find.text('Stok yakında'), findsOneWidget);
      expect(find.text('id: 5'), findsOneWidget);
    });

    testWidgets('SectionCard başlık ve içerik', (t) async {
      await pumpUi(t, const SectionCard(title: 'Özet', child: Text('içerik')));
      expect(find.text('Özet'), findsOneWidget);
      expect(find.text('içerik'), findsOneWidget);
    });
  });
}
