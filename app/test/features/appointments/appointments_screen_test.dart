import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/ui/states.dart';
import 'package:xc_asistan/core/util/dates.dart';

import '../support/feature_harness.dart';

Finder btn(String label) => buttonText<FilledButton>(label);

Map<String, dynamic> rec(FeatureHandle h, String id) =>
    h.db.appointments.firstWhere((a) => a['id'] == id);

void main() {
  group('Randevular (yönetici)', () {
    testWidgets('bugünün randevuları saat sırasıyla; ekle düğmesi var', (
      t,
    ) async {
      final h = await pumpFeature(t, initialLocation: '/appointments');
      final texts = allTexts(t);
      expect(texts, contains('Bugün — Cuma 20 Kasım · 3'));
      // Saat sırası: 09:30 önce, 14:00 sonra (üçüncü kart kaydırınca gelir).
      expect(texts.indexOf('09:30'), lessThan(texts.indexOf('14:00')));
      expect(texts.indexOf('09:30'), isNonNegative);
      await t.scrollUntilVisible(find.text('16:30'), 200);
      expect(find.text('Bakım · Mehmet Kaya'), findsOneWidget);
      expect(find.text('Randevu ekle'), findsOneWidget); // FAB
      expect(find.text('Yalnız benim'), findsOneWidget);
      // Yarının kartı bugün listesinde YOK.
      expect(find.text('Ön görüşme · Fatma Demir'), findsNothing);
      // İstek aralığı haftanın tamamı (Pzt 16 Kas 00:00 İstanbul).
      final q = h.adapter.requests.first.uri.queryParameters;
      expect(q['from'], '2026-11-15T21:00:00.000Z');
      expect(q['to'], '2026-11-22T21:00:00.000Z');
      expect(q.containsKey('assigned_user_id'), isFalse);
    });

    testWidgets('gün seçince o günün randevuları gelir (yarın)', (t) async {
      await pumpFeature(t, initialLocation: '/appointments');
      await t.tap(find.text('21'));
      await t.pump();
      expect(find.text('Yarın — Cumartesi 21 Kasım · 2'), findsOneWidget);
      expect(find.text('Ön görüşme · Fatma Demir'), findsOneWidget);
      expect(find.text('Teslim · Zeynep Arslan'), findsOneWidget);
      expect(find.text('Bakım · Mehmet Kaya'), findsNothing);
    });

    testWidgets('boş gün: eylem çağrılı boş durum', (t) async {
      await pumpFeature(t, initialLocation: '/appointments');
      await t.tap(find.text('16')); // Pazartesi: randevu yok
      await t.pump();
      expect(find.text('Bu gün için randevu yok'), findsOneWidget);
      expect(buttonText<FilledButton>('Randevu ekle'), findsOneWidget);
    });

    testWidgets('ay görünümüne geçiş', (t) async {
      await pumpFeature(t, initialLocation: '/appointments');
      await t.tap(find.text('Ay'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Kasım 2026'), findsOneWidget);
      // Ayın günleri ızgarada (ör. 30) ve hafta başlığı
      expect(find.text('30'), findsWidgets);
      expect(find.text('Pzt'), findsWidgets);
    });

    testWidgets('Tamamlandı tek dokunuş + Geri al', (t) async {
      final h = await pumpFeature(t, initialLocation: '/appointments');
      expect(rec(h, 'apt-2')['status'], 'beklemede');
      await tapVisible(t, btn('Tamamlandı').first);
      await h.settle();
      expect(rec(h, 'apt-2')['status'], 'tamamlandı');
      expect(find.text('Tamamlandı olarak işaretlendi.'), findsOneWidget);
      await t.tap(find.text('Geri al'));
      await h.settle();
      expect(rec(h, 'apt-2')['status'], 'beklemede');
    });

    testWidgets('İptal tek dokunuş', (t) async {
      final h = await pumpFeature(t, initialLocation: '/appointments');
      await tapVisible(t, buttonText<TextButton>('İptal').first);
      await h.settle();
      expect(rec(h, 'apt-2')['status'], 'iptal');
      expect(find.text('İptal edildi.'), findsOneWidget);
    });

    testWidgets('Ertele: 1 saat sonra', (t) async {
      final h = await pumpFeature(t, initialLocation: '/appointments');
      await tapVisible(t, buttonText<OutlinedButton>('Ertele').first);
      await h.settle();
      await t.tap(find.text('1 saat sonra'));
      await h.settle();
      final at = Ist.tryParse(rec(h, 'apt-2')['scheduled_at'] as String);
      expect(at, Ist.fromWall(2026, 11, 20, 15));
      expect(find.textContaining('Ertelendi'), findsOneWidget);
    });

    testWidgets('sunucu hatası: hata mesajı, durum değişmez', (t) async {
      final h = await pumpFeature(t, initialLocation: '/appointments');
      h.db.appointments.removeWhere(
        (a) => a['id'] == 'apt-2',
      ); // sunucuda yok → 404
      // Ekran eski veriyi tutuyor; PATCH 404 döner.
      await t.pump();
      expect(find.text('Montaj · Ahmet Şahin'), findsOneWidget);
      await tapVisible(t, btn('Tamamlandı').first);
      await h.settle();
      expect(find.text('Randevu bulunamadı.'), findsOneWidget);
    });

    testWidgets('hata durumu: Tekrar dene ile düzelir', (t) async {
      final h = await pumpFeature(
        t,
        initialLocation: '/appointments',
        failWith: offline(),
      );
      expect(find.text('Tekrar dene'), findsOneWidget);
      expect(find.textContaining('İnternet bağlantısı yok'), findsOneWidget);
      expect(find.text('Montaj · Ahmet Şahin'), findsNothing);
      h.adapter.failWith = null;
      await t.tap(find.text('Tekrar dene'));
      await h.settle();
      expect(find.text('Montaj · Ahmet Şahin'), findsOneWidget);
    });

    testWidgets('yükleniyor: iskelet', (t) async {
      final gate = Completer<void>();
      final h = await pumpFeature(
        t,
        initialLocation: '/appointments',
        gate: gate,
      );
      expect(find.byType(SkeletonBox), findsWidgets);
      gate.complete();
      await h.settle();
      expect(find.byType(SkeletonBox), findsNothing);
      expect(find.text('Montaj · Ahmet Şahin'), findsOneWidget);
    });
  });

  group('Randevular (saha)', () {
    testWidgets('yalnız kendi randevuları; ekleme yok; durum güncelleyebilir', (
      t,
    ) async {
      final h = await pumpFeature(
        t,
        role: UserRole.saha,
        initialLocation: '/appointments',
      );
      expect(
        h.adapter.requests.first.uri.queryParameters['assigned_user_id'],
        'me',
      );
      expect(find.text('Ön görüşme · Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Montaj · Ahmet Şahin'), findsOneWidget);
      expect(
        find.text('Bakım · Mehmet Kaya'),
        findsNothing,
      ); // yöneticiye atanmış
      expect(find.text('Randevu ekle'), findsNothing);
      expect(find.text('Yalnız benim'), findsNothing);
      await tapVisible(t, btn('Tamamlandı').first);
      await h.settle();
      expect(rec(h, 'apt-2')['status'], 'tamamlandı');
    });

    testWidgets('boş günde ekle eylemi yok', (t) async {
      await pumpFeature(
        t,
        role: UserRole.saha,
        initialLocation: '/appointments',
      );
      await t.tap(find.text('16'));
      await t.pump();
      expect(find.text('Bu gün için randevu yok'), findsOneWidget);
      expect(buttonText<FilledButton>('Randevu ekle'), findsNothing);
    });
  });

  group('Randevu detayı', () {
    testWidgets('bilgiler, telefon/adres eylemleri, bağlantılar', (t) async {
      final h = await pumpFeature(t, initialLocation: '/appointments');
      await t.tap(find.text('Montaj · Ahmet Şahin'));
      await h.settle();
      expect(h.location, '/appointments/apt-2');
      expect(find.text('Montaj'), findsWidgets);
      expect(find.text('Ahmet Şahin'), findsOneWidget);
      expect(find.text('Ara'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Yol tarifi'), findsOneWidget);
      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Sil'), findsOneWidget);
      expect(find.text('PRJ-501'), findsOneWidget); // demo: project_code
    });

    testWidgets(
      'sil: listeden hemen gizlenir, süre dolunca DELETE; geri al çalışır',
      (t) async {
        final h = await pumpFeature(t, initialLocation: '/appointments');
        await t.tap(find.text('Montaj · Ahmet Şahin'));
        await h.settle();
        await t.tap(buttonText<TextButton>('Sil'));
        await h.settle();
        expect(find.text('Randevu silindi.'), findsOneWidget);
        expect(h.location, '/appointments');
        expect(find.text('Montaj · Ahmet Şahin'), findsNothing); // gizli
        expect(rec(h, 'apt-2')['id'], 'apt-2'); // henüz sunucuda duruyor
        await t.pump(const Duration(seconds: 9));
        await h.settle();
        expect(h.db.appointments.any((a) => a['id'] == 'apt-2'), isFalse);
      },
    );

    testWidgets('sil + Geri al: kayıt korunur ve yeniden görünür', (t) async {
      final h = await pumpFeature(t, initialLocation: '/appointments');
      await t.tap(find.text('Montaj · Ahmet Şahin'));
      await h.settle();
      await t.tap(buttonText<TextButton>('Sil'));
      await h.settle();
      await t.tap(find.text('Geri al'));
      await t.pump(const Duration(seconds: 9));
      await h.settle();
      expect(h.db.appointments.any((a) => a['id'] == 'apt-2'), isTrue);
      expect(find.text('Montaj · Ahmet Şahin'), findsOneWidget);
    });

    testWidgets('saha: Sil yok, düzenleme etiketi sade', (t) async {
      final h = await pumpFeature(
        t,
        role: UserRole.saha,
        initialLocation: '/appointments',
      );
      await t.tap(find.text('Montaj · Ahmet Şahin'));
      await h.settle();
      expect(find.text('Sil'), findsNothing);
      expect(find.text('Not / zaman düzenle'), findsOneWidget);
    });

    testWidgets('bulunamayan kayıt: hata durumu', (t) async {
      final h = await pumpFeature(t, initialLocation: '/appointments');
      await h.push('/appointments/yok');
      expect(find.text('Randevu bulunamadı.'), findsOneWidget);
      expect(find.text('Tekrar dene'), findsOneWidget);
    });
  });
}
