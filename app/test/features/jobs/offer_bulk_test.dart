// İşler: teklif çoklu seçim, toplu durum/silme (kısmi hata, geri al), müşteri seçici, proje silme, bölümler.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/features/jobs/data/jobs_bulk.dart';
import 'package:xc_asistan/features/jobs/data/jobs_repository.dart';

import '../../helpers/app_harness.dart';

List<BulkTarget> _targets(int n) => [
  for (var i = 1; i <= n; i++) BulkTarget('o$i', 'OFR-$i · Kişi $i'),
];

/// Depo çağrısı: sahte saat altında takılmasın diye gerçek zamanda çalışır.
Future<T> api<T>(WidgetTester t, Future<T> Function() f) async {
  final r = await t.runAsync(() async {
    try {
      return (true, await f(), null as Object?);
    } catch (e) {
      return (false, null as T?, e);
    }
  });
  if (r!.$1) return r.$2 as T;
  throw r.$3!;
}

Future<void> _openSelection(WidgetTester t, AppHandle h) async {
  await t.longPress(find.text('OFR-1001'));
  await h.settle(10);
}

Future<void> _pumpLong(WidgetTester t, AppHandle h) async {
  await t.pump(const Duration(seconds: 9));
  await h.settle(20);
}

void main() {
  group('runBulk (yürütücü)', () {
    test(
      'toplu çağrı tüm sayıyı döndürürse hepsi başarılı; 50 üstü parçalanır',
      () async {
        final calls = <int>[];
        final out = await runBulk(
          targets: _targets(120),
          bulkCall: (ids) async {
            calls.add(ids.length);
            return ids.length;
          },
          single: (_) async => fail('tek tek çağrılmamalı'),
          isDone: (_) async => fail('doğrulama gerekmez'),
          skippedReason: 'x',
        );
        expect(calls, [50, 50, 20]);
        expect(out.allOk, true);
        expect(out.summary, '120 işlem: 120 başarılı');
      },
    );

    test(
      'sayı eksikse hatalılar tek tek doğrulanır ve özet nedenleri taşır',
      () async {
        final progress = <int>[];
        final out = await runBulk(
          targets: _targets(5),
          bulkCall: (ids) async => 4,
          single: (_) async {},
          isDone: (id) async => id != 'o3',
          skippedReason: 'Atlandı',
          onProgress: (d, t) => progress.add(d),
        );
        expect(out.summary, '5 işlem: 4 başarılı, 1 hatalı');
        expect(out.failures.single.target.id, 'o3');
        expect(out.failures.single.reason, 'Atlandı');
        expect(out.succeededIds, ['o1', 'o2', 'o4', 'o5']);
        expect(progress.last, 5);
      },
    );

    test(
      'toplu çağrı sunucu hatası verirse tek tek uygulanır, eşzamanlılık <= 3',
      () async {
        var running = 0;
        var peak = 0;
        final out = await runBulk(
          targets: _targets(10),
          bulkCall: (ids) async =>
              throw const AppException(AppErrorCode.server, 'Sunucu hatası'),
          single: (id) async {
            running++;
            if (running > peak) peak = running;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            running--;
            if (id == 'o7') {
              throw const AppException(AppErrorCode.forbidden, 'Yetkiniz yok.');
            }
          },
          isDone: (_) async => true,
          skippedReason: 'x',
        );
        expect(peak, lessThanOrEqualTo(bulkConcurrency));
        expect(peak, greaterThan(1));
        expect(out.summary, '10 işlem: 9 başarılı, 1 hatalı');
        expect(out.failures.single.reason, 'Yetkiniz yok.');
      },
    );

    test(
      'ağ hatasında kayıtlar tek tek denenmez, hepsi hatalı sayılır',
      () async {
        var singles = 0;
        final out = await runBulk(
          targets: _targets(4),
          bulkCall: (ids) async =>
              throw const AppException(AppErrorCode.network, 'Bağlantı yok.'),
          single: (_) async => singles++,
          isDone: (_) async => true,
          skippedReason: 'x',
        );
        expect(singles, 0);
        expect(out.ok, 0);
        expect(out.failures, hasLength(4));
      },
    );
  });

  group('Teklifler çoklu seçim (DEMO)', () {
    testWidgets('uzun basış seçim kipini açar; çubuk, sayaç ve Temizle', (
      t,
    ) async {
      final h = await pumpXcApp(t, role: 'admin', initialLocation: '/jobs');
      expect(find.text('6 KAYIT'), findsOneWidget);
      await _openSelection(t, h);
      expect(find.text('1 seçili'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
      // başka karta dokunmak seçimi değiştirir (ayrıntıya gitmez)
      await t.tap(find.text('OFR-1002'));
      await h.settle(6);
      expect(find.text('2 seçili'), findsOneWidget);
      expect(h.location, '/jobs');
      await t.tap(find.text('Temizle'));
      await h.settle(6);
      expect(find.text('Görünenleri seç (6)'), findsOneWidget);
      await t.tap(find.byTooltip('Seçim kipinden çık'));
      await h.settle(6);
      expect(find.text('6 KAYIT'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Seç düğmesi ve Görünenleri seç', (t) async {
      final h = await pumpXcApp(t, role: 'admin', initialLocation: '/jobs');
      await t.tap(find.text('Seç'));
      await h.settle(6);
      await t.tap(find.text('Görünenleri seç (6)'));
      await h.settle(6);
      expect(find.text('6 seçili'), findsOneWidget);
      await t.tap(find.text('6 seçili'));
      await h.settle(6);
      expect(find.text('Görünenleri seç (6)'), findsOneWidget);
    });

    testWidgets(
      'toplu durum: İncelendi uygulanır, Geri al eski durumlara döner',
      (t) async {
        final h = await pumpXcApp(t, role: 'admin', initialLocation: '/jobs');
        final repo = h.container.read(jobsRepositoryProvider);
        await _openSelection(t, h);
        await t.tap(find.text('OFR-1002'));
        await h.settle(6);
        await t.tap(find.text('Durum değiştir'));
        await h.settle(10);
        await t.tap(find.text('İncelendi').last);
        await h.settle(30);
        expect((await api(t, () => repo.offer('off-1'))).status, 'İncelendi');
        expect((await api(t, () => repo.offer('off-2'))).status, 'İncelendi');
        expect(
          find.textContaining('2 fiyat teklifi: İncelendi'),
          findsOneWidget,
        );
        await t.tap(find.text('Geri al'));
        await h.settle(30);
        expect((await api(t, () => repo.offer('off-1'))).status, 'Yeni');
        expect((await api(t, () => repo.offer('off-2'))).status, 'Yeni');
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'kısmi başarısızlık: personel kabul edilmiş teklifi değiştiremez -> özet',
      (t) async {
        final h = await pumpXcApp(
          t,
          role: 'personel',
          initialLocation: '/jobs',
        );
        final repo = h.container.read(jobsRepositoryProvider);
        await t.tap(find.text('Seç'));
        await h.settle(6);
        await t.tap(find.text('Görünenleri seç (6)'));
        await h.settle(6);
        await t.tap(find.text('Durum değiştir'));
        await h.settle(10);
        await t.tap(find.text('Reddedildi').last);
        await h.settle(40);
        expect(find.text('Toplu durum değiştirme'), findsOneWidget);
        expect(find.text('6 işlem: 5 başarılı, 1 hatalı'), findsOneWidget);
        expect(find.textContaining('OFR-1005'), findsWidgets);
        expect(find.textContaining('Atlandı'), findsOneWidget);
        expect(
          (await api(t, () => repo.offer('off-5'))).status,
          'Kabul Edildi',
        );
        expect((await api(t, () => repo.offer('off-1'))).status, 'Reddedildi');
        await t.tap(find.text('Tamam'));
        await h.settle(10);
        // hatalı kayıt seçili bırakıldı
        expect(find.text('1 seçili'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('toplu silme: onay, Geri al kayıtları geri getirir', (t) async {
      final h = await pumpXcApp(t, role: 'admin', initialLocation: '/jobs');
      final repo = h.container.read(jobsRepositoryProvider);
      await _openSelection(t, h);
      await t.tap(find.text('OFR-1002'));
      await h.settle(6);
      await t.tap(find.text('Sil'));
      await h.settle(10);
      expect(find.text('2 fiyat teklifi silinsin mi?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Sil'));
      await h.settle(10);
      expect(find.text('OFR-1001'), findsNothing);
      expect(find.text('4 KAYIT'), findsOneWidget);
      await t.tap(find.text('Geri al'));
      await h.settle(30);
      expect(find.text('OFR-1001'), findsOneWidget);
      expect(
        (await api(t, () => repo.offer('off-1'))).code,
        'OFR-1001',
      ); // sunucuda silinmedi
      expect(t.takeException(), isNull);
    });

    testWidgets('toplu silme: süre dolunca gerçek DELETE yapılır', (t) async {
      final h = await pumpXcApp(t, role: 'admin', initialLocation: '/jobs');
      final repo = h.container.read(jobsRepositoryProvider);
      await _openSelection(t, h);
      await t.tap(find.text('Sil'));
      await h.settle(10);
      await t.tap(find.widgetWithText(FilledButton, 'Sil'));
      await h.settle(10);
      await _pumpLong(t, h);
      await expectLater(
        api(t, () => repo.offer('off-1')),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.notFound,
          ),
        ),
      );
      expect(find.text('OFR-1001'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'rol: muhasebe toplu silme düğmesi görmez; saha İşler yetkisiz',
      (t) async {
        final h = await pumpXcApp(
          t,
          role: 'muhasebe',
          initialLocation: '/jobs',
        );
        await _openSelection(t, h);
        expect(find.text('Durum değiştir'), findsOneWidget);
        expect(find.text('Sil'), findsNothing);
        expect(t.takeException(), isNull);
        expect(h.location, '/jobs');
      },
    );

    testWidgets('360dp ve 1.3x yazı ölçeği: seçim çubuğu taşmaz', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final h = await pumpXcApp(
        t,
        role: 'admin',
        initialLocation: '/jobs',
        logicalSize: const Size(360, 740),
      );
      await _openSelection(t, h);
      expect(find.text('Durum değiştir'), findsOneWidget);
      expect(find.text('Sil'), findsOneWidget);
      await t.tap(find.text('Durum değiştir'));
      await h.settle(10);
      await t.tap(find.text('Kabul Edildi').last);
      await h.settle(10);
      expect(find.textContaining('kabul edilsin mi?'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('Müşteri seçici entegrasyonu', () {
    testWidgets('yeni teklif: mevcut müşteriden seçince alanlar dolar', (
      t,
    ) async {
      final h = await pumpXcApp(
        t,
        role: 'admin',
        initialLocation: '/jobs/offers/new',
      );
      expect(find.text('Mevcut müşteriden seç'), findsOneWidget);
      await t.tap(find.text('Mevcut müşteriden seç'));
      await h.settle(20);
      final tile = find.byType(ListTile).first;
      final title = (t.widget<ListTile>(tile).title as Text).data!;
      await t.tap(tile);
      await h.settle(20);
      final fields = find.byType(TextFormField);
      expect(t.widget<TextFormField>(fields.at(0)).controller!.text, title);
      expect(
        t.widget<TextFormField>(fields.at(1)).controller!.text,
        isNotEmpty,
      );
      // yeni müşteri akışı bozulmadı: elle yazılabilir
      await t.enterText(fields.at(0), 'Yeni Kişi');
      expect(
        t.widget<TextFormField>(fields.at(0)).controller!.text,
        'Yeni Kişi',
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('yeni proje: müşteri seçilince ad dolar', (t) async {
      final h = await pumpXcApp(
        t,
        role: 'admin',
        initialLocation: '/jobs/projects/new',
      );
      await t.tap(find.text('Mevcut müşteriden seç'));
      await h.settle(20);
      final tile = find.byType(ListTile).first;
      final title = (t.widget<ListTile>(tile).title as Text).data!;
      await t.tap(tile);
      await h.settle(20);
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        title,
      );
    });

    testWidgets('teklif düzenlemede seçici yok', (t) async {
      await pumpXcApp(
        t,
        role: 'admin',
        initialLocation: '/jobs/offers/off-1/edit',
      );
      expect(find.text('Mevcut müşteriden seç'), findsNothing);
    });
  });

  group('Proje silme ve bölümler', () {
    testWidgets(
      'proje listesi: Devam eden / Tamamlananlar başlıkları sayaçla',
      (t) async {
        final h = await pumpXcApp(t, role: 'admin', initialLocation: '/jobs');
        await t.tap(find.textContaining('İşler ('));
        await h.settle(20);
        expect(find.textContaining('Devam eden'), findsWidgets);
        expect(find.byType(Semantics), findsWidgets);
        final header = find.bySemanticsLabel(
          RegExp(r'^Devam eden .*, \d+ kayıt$'),
        );
        expect(header, findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'admin: proje sil -> uyarı + onay kutusu -> süre sonunda silinir',
      (t) async {
        final h = await pumpXcApp(
          t,
          role: 'admin',
          initialLocation: '/jobs/projects/prj-1',
        );
        final repo = h.container.read(jobsRepositoryProvider);
        await t.tap(find.byTooltip('Diğer işlemler'));
        await h.settle(10);
        await t.tap(find.textContaining(' sil'));
        await h.settle(10);
        expect(find.textContaining('Birlikte silinecekler'), findsOneWidget);
        expect(find.textContaining('ödeme'), findsWidgets);
        // ödeme olduğundan onay kutusu işaretlenmeden Sil kapalı
        final del = find.widgetWithText(FilledButton, 'Sil');
        expect(t.widget<FilledButton>(del).onPressed, isNull);
        await t.tap(find.byType(CheckboxListTile));
        await h.settle(6);
        await t.tap(del);
        await h.settle(10);
        await _pumpLong(t, h);
        await expectLater(
          api(t, () => repo.projectFull('prj-1')),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              AppErrorCode.notFound,
            ),
          ),
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('proje sil: Geri al gerçek silmeyi iptal eder', (t) async {
      final h = await pumpXcApp(
        t,
        role: 'admin',
        initialLocation: '/jobs/projects/prj-1',
      );
      final repo = h.container.read(jobsRepositoryProvider);
      await t.tap(find.byTooltip('Diğer işlemler'));
      await h.settle(10);
      await t.tap(find.textContaining(' sil'));
      await h.settle(10);
      await t.tap(find.byType(CheckboxListTile));
      await h.settle(6);
      await t.tap(find.widgetWithText(FilledButton, 'Sil'));
      await h.settle(10);
      await t.tap(find.text('Geri al'));
      await _pumpLong(t, h);
      expect(
        (await api(t, () => repo.projectFull('prj-1'))).project.id,
        'prj-1',
      );
    });

    testWidgets('personel: proje sil menüsü yok; sunucu da 403 verir', (
      t,
    ) async {
      final h = await pumpXcApp(
        t,
        role: 'personel',
        initialLocation: '/jobs/projects/prj-1',
      );
      expect(find.byTooltip('Diğer işlemler'), findsNothing);
      final repo = h.container.read(jobsRepositoryProvider);
      await expectLater(
        api(t, () => repo.deleteProject('prj-1')),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.forbidden,
          ),
        ),
      );
    });
  });
}
