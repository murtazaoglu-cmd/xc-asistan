import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/demo/demo_router.dart';
import 'package:xc_asistan/features/home/application/home_controller.dart';
import 'package:xc_asistan/features/home/data/photo_source.dart';

import '../support/feature_harness.dart';

class FakePhotos implements PhotoSource {
  FakePhotos(this.photo);
  final PickedPhoto? photo;
  final List<PhotoOrigin> calls = [];
  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async {
    calls.add(origin);
    return photo;
  }
}

void main() {
  testWidgets('admin: 4 sayaç, tahsilat özeti, asistan özeti', (t) async {
    await pumpFeature(t);
    final txt = allTexts(t);
    expect(txt, contains('Randevu'));
    expect(txt, contains('Tahsilat'));
    expect(txt, contains('Teklif'));
    expect(txt.any((e) => e.startsWith('Geciken')), isTrue);
    expect(find.text('Günün özeti'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Tahsilat özeti'), 400);
    expect(find.text('Tahsilat özeti'), findsOneWidget);
  });

  testWidgets('personel: Tahsilat sayacı ve tahsilat özeti yok', (t) async {
    await pumpFeature(t, role: UserRole.personel);
    expect(find.text('Tahsilat'), findsNothing);
    expect(find.text('Tahsilat özeti'), findsNothing);
    expect(find.text('Randevu'), findsOneWidget);
  });

  testWidgets('saha: büyük düğmeler, finans/teklif yok', (t) async {
    // Ahem yazı tipi metni şişirir: iki sütunlu düğmeler için geniş yüzey.
    await pumpFeature(t, role: UserRole.saha, surface: const Size(2400, 4200));
    for (final l in ['Konum / Yol tarifi', 'Fotoğraf yükle', 'İş tamamla']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    expect(find.text('Tahsilat'), findsNothing);
    expect(find.text('Tahsilat özeti'), findsNothing);
    expect(find.text('Günün özeti'), findsNothing);
    expect(allTexts(t).any((e) => e.contains('talepleri')), isFalse);
    expect(t.getSize(find.text('İş tamamla')).height, greaterThan(0));
  });

  testWidgets('hata: çevrimdışı ve veri yok → hata durumu + tekrar dene', (
    t,
  ) async {
    final h = await pumpFeature(t, failWith: offline());
    expect(find.byIcon(Icons.refresh), findsWidgets);
    expect(find.text('Günün özeti'), findsNothing);
    // Bağlantı gelince yeniden dene
    h.adapter.failWith = null;
    final retry = find.text('Tekrar dene');
    expect(retry, findsOneWidget);
    await t.tap(retry);
    await h.settle(20);
    expect(find.text('Günün özeti'), findsOneWidget);
  });

  testWidgets('yenileme hatasında eski veri korunur + bayat bandı', (t) async {
    final h = await pumpFeature(t);
    expect(find.text('Günün özeti'), findsOneWidget);
    h.adapter.failWith = offline();
    unawaited(
      h.container.read(homeControllerProvider.notifier).refresh(silent: true),
    );
    await h.settle(20);
    expect(find.text('Günün özeti'), findsOneWidget);
    expect(
      find.text('Bağlantı yok. Son alınan bilgiler gösteriliyor.'),
      findsOneWidget,
    );
  });

  testWidgets('hatırlatıcı tamamla: listeden düşer, geri al döner', (t) async {
    final h = await pumpFeature(t);
    await t.scrollUntilVisible(find.textContaining('Hatırlatıcılar ('), 400);
    final before = find.textContaining('Hatırlatıcılar (');
    expect(before, findsOneWidget);
    final title = (t.widget(before) as Text).data!;
    await tapVisible(t, find.byTooltip('Tamamla').first);
    await h.settle();
    expect(find.text('Hatırlatıcı tamamlandı.'), findsOneWidget);
    expect(
      (t.widget(find.textContaining('Hatırlatıcılar (')) as Text).data,
      isNot(title),
    );
    await t.tap(find.text('Geri al'));
    await h.settle(20);
    expect(
      (t.widget(find.textContaining('Hatırlatıcılar (')) as Text).data,
      title,
    );
  });

  testWidgets('hatırlatıcı ertele: yeni kayıt + eskisi tamamlandı', (t) async {
    final h = await pumpFeature(t);
    await t.scrollUntilVisible(find.textContaining('Hatırlatıcılar ('), 400);
    await tapVisible(t, find.byTooltip('Ertele').first);
    await h.settle(20);
    await t.tap(find.text('Yarın 09:00').first);
    await h.settle(20);
    final methods = h.adapter.requests.map((r) => '${r.method} ${r.uri.path}');
    expect(methods, contains('POST /api/reminders'));
    expect(
      methods.where((m) => m.startsWith('PATCH /api/reminders')),
      isNotEmpty,
    );
    expect(find.textContaining('Ertelendi'), findsOneWidget);
  });

  testWidgets('saha: fotoğraf yükle → kamera → yüklendi', (t) async {
    final photos = FakePhotos(const PickedPhoto('/dev/null', 'a.jpg'));
    final h = await pumpFeature(
      t,
      role: UserRole.saha,
      surface: const Size(2400, 4200),
      overrides: [photoSourceProvider.overrideWithValue(photos)],
    );
    await tapVisible(t, find.text('Fotoğraf yükle'));
    await h.settle();
    // İş seçici ya da doğrudan kaynak sheet'i
    expect(find.text('Fotoğraf hangi işe eklensin?'), findsOneWidget);
    await t.tap(find.text('14:00 Montaj · Ahmet Şahin'));
    await h.settle();
    await t.tap(find.text('Kamera'));
    await h.settle(30);
    expect(photos.calls, [PhotoOrigin.camera]);
  });

  testWidgets('sakin gün: randevu/talep yoksa boş gün kartı', (t) async {
    final empty = RoutesAdapter([
      DemoRoute(
        'GET',
        '/mobile/home',
        (req) => DemoResponse.json({
          'generatedAt': '2026-11-20T08:00:00.000Z',
          'user': {'id': 'u', 'name': 'Ad', 'role': 'admin'},
          'appointments': {'today': [], 'tomorrow': []},
          'newOffers': {'count': 0, 'latest': []},
          'overdueProjects': {'count': 0, 'items': []},
          'finance': null,
          'reminders': {'today': [], 'overdue': []},
          'lowStock': {'count': 0, 'items': []},
        }),
      ),
    ]);
    await pumpFeature(t, adapter: empty);
    expect(find.text('Bugün sakin bir gün'), findsOneWidget);
  });
}
