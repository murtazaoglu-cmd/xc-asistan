import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/demo/demo_router.dart';
import 'package:xc_asistan/core/util/dates.dart';

import '../support/feature_harness.dart';

Finder chip(String label) => find.widgetWithText(ChoiceChip, label);
Finder field(String label) => find.widgetWithText(TextField, label);

Future<void> tapChip(WidgetTester t, String label) async {
  await tapVisible(t, chip(label));
  await t.pump();
}

Future<void> save(
  WidgetTester t,
  FeatureHandle h, [
  String label = 'Randevu ekle',
]) async {
  await t.tap(buttonText<FilledButton>(label));
  await h.settle();
}

void main() {
  group('Yeni randevu formu', () {
    testWidgets('boş kayıtta alan hataları; istek gönderilmez', (t) async {
      final h = await pumpFeature(t, initialLocation: '/appointments/new');
      final before = h.adapter.requests.length;
      await save(t, h);
      expect(find.text('Tür seçin.'), findsOneWidget);
      expect(find.text('Müşteri seçin ya da ad girin.'), findsWidgets);
      expect(find.text('Tarih ve saat seçin.'), findsOneWidget);
      expect(h.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      expect(h.adapter.requests.length, before);
    });

    testWidgets('geçersiz telefon uyarısı', (t) async {
      final h = await pumpFeature(t, initialLocation: '/appointments/new');
      await t.enterText(field('Telefon'), '123');
      await save(t, h);
      expect(find.text('Geçerli bir telefon numarası girin.'), findsOneWidget);
    });

    testWidgets('doldur → kaydet: POST gövdesi, liste yenilenir, Geri al', (
      t,
    ) async {
      final h = await pumpFeature(t, initialLocation: '/appointments');
      await tapVisible(t, find.text('Randevu ekle').first);
      await h.settle();
      expect(h.location.startsWith('/appointments/new'), isTrue);
      await tapChip(t, 'Ön görüşme');
      await t.enterText(field('Müşteri adı'), 'Veli Can');
      await t.enterText(field('Telefon'), '0532 999 88 77');
      await t.enterText(field('Adres'), 'Gündoğan Mah. 4');
      await tapChip(t, 'Yarın');
      await tapChip(t, '10:00');
      await save(t, h);
      // Forma geri dönüldü, liste yenilendi
      expect(h.location, '/appointments');
      final created = h.db.appointments.last;
      expect(
        created['type'],
        'Keşif',
      ); // sözlük etiketi gösterim içindir; kabloya api değeri gider
      expect(created['customer_name'], 'Veli Can');
      expect(created['customer_phone'], '0532 999 88 77');
      expect(created['address'], 'Gündoğan Mah. 4');
      expect(created['assigned_user_id'], 'u-admin');
      expect(
        Ist.tryParse(created['scheduled_at'] as String),
        Ist.fromWall(2026, 11, 21, 10),
      );
      final post = h.adapter.requests.firstWhere((r) => r.method == 'POST');
      expect((post.data as Map)['scheduled_at'], '2026-11-21T10:00:00+03:00');
      expect(find.text('Randevu eklendi.'), findsOneWidget);
      // Geri al → silinir
      await t.tap(find.text('Geri al'));
      await h.settle();
      expect(
        h.db.appointments.any((a) => a['customer_name'] == 'Veli Can'),
        isFalse,
      );
    });

    testWidgets('gün parametresi formu önceden doldurur (09:00)', (t) async {
      final h = await pumpFeature(
        t,
        initialLocation: '/appointments/new?day=2026-11-23T21:00:00.000Z', // 24 Kas 00:00 İst.
      );
      expect(
        find.textContaining('Salı'),
        findsNothing,
      ); // gün adı kısa gösterilir
      expect(find.textContaining('09:00'), findsWidgets);
      expect(find.textContaining('24 Kas 2026'), findsOneWidget);
      expect(h.location.contains('day='), isTrue);
    });

    testWidgets(
      'aynı kişide yakın randevu: çakışma uyarısı (kaydı engellemez)',
      (t) async {
        final h = await pumpFeature(t, initialLocation: '/appointments/new');
        // Yönetici (ben) bugün 16:30'da Bakım randevusu var.
        await tapChip(t, 'Bugün');
        await tapChip(t, '16:00');
        await h.settle();
        expect(
          find.textContaining('Aynı kişide bu saate yakın'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Yine de kaydedebilirsiniz'),
          findsOneWidget,
        );
        // Başka kişiye atayınca uyarı kalkar (Saha Ekibi 09:30/14:00; 16:00 uzak değil: 14:00'e 2 saat).
        await tapChip(t, 'Saha Ekibi · Saha');
        await h.settle();
        expect(find.textContaining('Aynı kişide'), findsNothing);
        // 14:00 civarı saha için çakışır
        await tapChip(t, '14:00');
        await h.settle();
        expect(
          find.textContaining('Aynı kişide bu saate yakın'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'teklif seçici: arama, seçim bağlantı kurar, ad tekrar gönderilmez',
      (t) async {
        final h = await pumpFeature(t, initialLocation: '/appointments/new');
        await t.tap(find.text('Müşteri, fiyat teklifi ya da iş seç'));
        await h.settle();
        expect(find.text('Ayşe Yılmaz'), findsOneWidget);
        await t.enterText(
          find.widgetWithText(TextField, 'Ad, telefon ya da kod ile ara'),
          'mehmet',
        );
        await t.pump(const Duration(milliseconds: 400));
        await h.settle();
        expect(find.text('Ayşe Yılmaz'), findsNothing);
        expect(find.text('Mehmet Kaya'), findsOneWidget);
        await t.tap(find.text('Mehmet Kaya'));
        await h.settle();
        // Ad/telefon formda önceden dolu, bağlantı etiketi görünür
        expect(find.text('Bağlı kayıt'), findsOneWidget);
        expect(
          (t.widget<TextField>(field('Müşteri adı')).controller!.text),
          'Mehmet Kaya',
        );
        await tapChip(t, 'Ön görüşme');
        await tapChip(t, 'Yarın');
        await tapChip(t, '11:00');
        await save(t, h);
        final post =
            h.adapter.requests.firstWhere((r) => r.method == 'POST').data
                as Map;
        expect(post['offer_id'], 'off-2');
        expect(post.containsKey('customer_name'), isFalse); // sunucu çözümler
        expect(post.containsKey('customer_phone'), isFalse);
      },
    );

    testWidgets('sunucu 403 mesajı formda gösterilir, form açık kalır', (
      t,
    ) async {
      final h = await pumpFeature(t, initialLocation: '/appointments/new');
      await tapChip(t, 'Montaj');
      await t.enterText(field('Müşteri adı'), 'Ali');
      await tapChip(t, 'Yarın');
      await tapChip(t, '09:00');
      // Başka ekibin kişisine atama → sunucu reddeder (demo: sahte 403 için başarısız rota)
      h.adapter.routes.insert(
        0,
        DemoRoute(
          'POST',
          '/appointments',
          (req) => DemoResponse.error(403, 'Bu işlem için yetkiniz yok.'),
        ),
      );
      await save(t, h);
      expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
      expect(h.location.startsWith('/appointments/new'), isTrue);
    });

    testWidgets('saha yeni randevu ekleyemez', (t) async {
      await pumpFeature(
        t,
        role: UserRole.saha,
        initialLocation: '/appointments/new',
      );
      expect(find.text('Bu işlem için yetkiniz yok'), findsOneWidget);
      expect(find.text('Tür'), findsNothing);
    });
  });

  group('Randevu düzenleme', () {
    testWidgets('yönetici: yalnız değişen alan PATCH edilir', (t) async {
      final h = await pumpFeature(t, initialLocation: '/appointments');
      await h.push('/appointments/apt-2/edit');
      expect(field('Müşteri adı'), findsOneWidget);
      expect(
        t.widget<TextField>(field('Müşteri adı')).controller!.text,
        'Ahmet Şahin',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Not'),
        'Anahtarı teslim al',
      );
      await save(t, h, 'Kaydet');
      final patch =
          h.adapter.requests.lastWhere((r) => r.method == 'PATCH').data as Map;
      expect(patch, {'notes': 'Anahtarı teslim al'});
      expect(
        h.db.appointments.firstWhere((a) => a['id'] == 'apt-2')['notes'],
        'Anahtarı teslim al',
      );
    });

    testWidgets(
      'saha: yalnız durum/zaman/not alanları; yasak alan gönderilmez',
      (t) async {
        final h = await pumpFeature(
          t,
          role: UserRole.saha,
          initialLocation: '/appointments',
        );
        await h.push('/appointments/apt-2/edit');
        expect(find.text('Tür'), findsNothing);
        expect(find.text('Atanan kişi'), findsNothing);
        expect(field('Adres'), findsNothing);
        expect(find.text('Durum'), findsOneWidget);
        await tapChip(t, 'Tamamlandı');
        await save(t, h, 'Kaydet');
        final patch =
            h.adapter.requests.lastWhere((r) => r.method == 'PATCH').data
                as Map;
        expect(
          patch.keys.toSet().difference({'status', 'notes', 'scheduled_at'}),
          isEmpty,
        );
        expect(patch['status'], 'tamamlandı');
        expect(
          h.db.appointments.firstWhere((a) => a['id'] == 'apt-2')['status'],
          'tamamlandı',
        );
      },
    );

    testWidgets('kayıt yoksa hata durumu', (t) async {
      final h = await pumpFeature(t, initialLocation: '/appointments');
      await h.push('/appointments/yok/edit');
      expect(find.text('Randevu bulunamadı.'), findsOneWidget);
    });
  });
}
