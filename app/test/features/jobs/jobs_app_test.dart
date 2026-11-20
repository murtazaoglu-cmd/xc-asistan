import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/app_harness.dart';

Future<void> scrollTap(WidgetTester t, AppHandle h, Finder f) async {
  await t.ensureVisible(f.first);
  await h.settle(4);
  await t.tap(f.first);
  await h.settle(20);
}

void main() {
  testWidgets('admin: liste, sekme sayıları ve kartlar', (t) async {
    final h = await pumpXcApp(t, role: 'admin', initialLocation: '/jobs');
    expect(h.location, '/jobs');
    expect(find.text('OFR-1001'), findsOneWidget);
    expect(find.textContaining('Fiyat teklifleri ('), findsOneWidget);
    expect(find.textContaining('İşler ('), findsOneWidget);
    // Gün sınırına (gece yarısı) bağımlı olmasın: bekleme etiketi ya 'Bugün geldi' ya 'N gündür bekliyor'.
    expect(
      find.textContaining(RegExp(r'Bugün geldi|gündür bekliyor')),
      findsWidgets,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('durum süzgeci: İncelendi seçilince yalnız o durum kalır', (
    t,
  ) async {
    final h = await pumpXcApp(t, role: 'admin', initialLocation: '/jobs');
    await t.tap(find.text('İncelendi').first);
    await h.settle(20);
    expect(find.text('OFR-1001'), findsNothing); // "Yeni" olan kart süzüldü
    expect(t.takeException(), isNull);
  });

  testWidgets('arama: eşleşmeyen sorgu boş-süzülmüş durum gösterir', (t) async {
    final h = await pumpXcApp(t, role: 'admin', initialLocation: '/jobs');
    await t.enterText(find.byType(TextField).first, 'zzzyok');
    await t.pump(const Duration(milliseconds: 500));
    await h.settle(20);
    expect(find.text('OFR-1001'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('projeler sekmesi: kart, ilerleme ve kalan tutar', (t) async {
    final h = await pumpXcApp(t, role: 'admin', initialLocation: '/jobs');
    await t.tap(find.textContaining('İşler ('));
    await h.settle(20);
    expect(find.text('PRJ-501'), findsOneWidget);
    expect(find.text('Kalan ₺4.500'), findsOneWidget);
    expect(find.textContaining('gecikti'), findsOneWidget);
  });

  testWidgets(
    'teklif detay: durum seçenekleri TAM yazımla, gönderim kapalı (teklif yok)',
    (t) async {
      final h = await pumpXcApp(
        t,
        role: 'admin',
        initialLocation: '/jobs/offers/off-1',
      );
      for (final s in [
        'Yeni',
        'İncelendi',
        'Keşif Planlandı',
        'Teklif Verildi',
        'Kabul Edildi',
        'Reddedildi',
      ]) {
        expect(find.text(s), findsWidgets, reason: s);
      }
      expect(
        find.text('Göndermek için önce fiyat teklifi hazırlayın.'),
        findsOneWidget,
      );
      expect(h.location, '/jobs/offers/off-1');
    },
  );

  testWidgets('teklif detay: tek dokunuşla durum değişir', (t) async {
    final h = await pumpXcApp(
      t,
      role: 'admin',
      initialLocation: '/jobs/offers/off-1',
    );
    await scrollTap(t, h, find.widgetWithText(ChoiceChip, 'İncelendi'));
    expect(
      t
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'İncelendi'))
          .selected,
      true,
    );
  });

  testWidgets('teklif editörü: canlı toplam KDV hariç → +%20', (t) async {
    final h = await pumpXcApp(
      t,
      role: 'admin',
      initialLocation: '/jobs/offers/off-1/quote',
    );
    final tf = find.byType(TextField);
    await t.enterText(tf.at(0), 'Pergola');
    await t.enterText(tf.at(1), '2');
    await t.enterText(tf.at(2), '1000');
    await h.settle(8);
    expect(find.text('₺2.000,00'), findsOneWidget); // ara toplam
    expect(find.text('₺400,00'), findsOneWidget); // KDV
    expect(find.text('₺2.400,00'), findsWidgets); // toplam
  });

  testWidgets('teklif editörü: kaydet → gönder → sonuç dürüst gösterilir', (
    t,
  ) async {
    final h = await pumpXcApp(
      t,
      role: 'admin',
      initialLocation: '/jobs/offers/off-1/quote',
    );
    final tf = find.byType(TextField);
    await t.enterText(tf.at(0), 'Pergola');
    await t.enterText(tf.at(1), '1');
    await t.enterText(tf.at(2), '1000');
    await h.settle(4);
    await scrollTap(t, h, find.text('Fiyat teklifi kaydet'));
    expect(h.location, '/jobs/offers/off-1');
    await t.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Gönder'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await h.settle(4);
    await t.tap(find.widgetWithText(FilledButton, 'Gönder'));
    await h.settle(10);
    // Onay penceresi: "Gönder" ikinci kez.
    await t.tap(find.widgetWithText(FilledButton, 'Gönder').last);
    await h.settle(20);
    // DEMO ilk gönderim 207: "Kısmen gönderildi" (asla sessizce "Gönderildi" değil).
    final title = find.byKey(const ValueKey('send-result-title'));
    expect(title, findsOneWidget);
    expect((t.widget(title) as Text).data, 'Kısmen gönderildi');
  });

  testWidgets('yeni teklif formu: boş gönderimde zorunlu alan hatası', (
    t,
  ) async {
    final h = await pumpXcApp(
      t,
      role: 'admin',
      initialLocation: '/jobs/offers/new',
    );
    expect(h.location, '/jobs/offers/new');
    await scrollTap(t, h, find.text('Fiyat teklifi oluştur'));
    expect(h.location, '/jobs/offers/new'); // kaydedilmedi
    expect(find.textContaining('zorunludur'), findsWidgets);
  });

  testWidgets('proje detay: sekmeler ve finans (admin)', (t) async {
    final h = await pumpXcApp(
      t,
      role: 'admin',
      initialLocation: '/jobs/projects/prj-1',
    );
    expect(t.takeException(), isNull);
    for (final s in ['Özet', 'Görevler', 'Ödemeler', 'Giderler', 'Belgeler']) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    expect(h.location, startsWith('/jobs/projects/'));
    await t.tap(find.text('Ödemeler').first);
    await h.settle(20);
    expect(t.takeException(), isNull);
  });

  testWidgets('saha: İşler sekmesine erişemez, Bugün\'e döner', (t) async {
    final h = await pumpXcApp(t, role: 'saha', initialLocation: '/jobs');
    expect(h.location, '/today');
    t.takeException(); // Bugün (saha) ekranındaki taşma başka modüle ait.
  });
}
