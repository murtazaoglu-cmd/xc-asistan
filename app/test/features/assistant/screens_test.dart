import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/features/assistant/presentation/assistant_screen.dart';
import 'package:xc_asistan/features/assistant/presentation/briefing_screen.dart';
import 'package:xc_asistan/features/assistant/presentation/closure_screen.dart';
import 'package:xc_asistan/features/assistant/presentation/consents_screen.dart';
import 'package:xc_asistan/features/assistant/presentation/inbox_screen.dart';
import 'package:xc_asistan/features/assistant/presentation/insights_screen.dart';
import 'package:xc_asistan/features/assistant/presentation/notification_prefs_screen.dart';
import 'package:xc_asistan/features/assistant/presentation/suggestions_screen.dart';

import 'harness.dart';

Future<void> _enter(WidgetTester t, String text) async {
  await t.enterText(find.byType(TextField).last, text);
  await t.tap(find.byTooltip('Gönder'));
  await settle(t);
}

void main() {
  group('Asistan sohbet ekranı', () {
    testWidgets('yönetici: hızlı çipler tam', (t) async {
      await pumpScreen(t, const AssistantScreen());
      await settle(t);
      for (final s in ['Randevu ekle', 'Ödeme ekle', 'Bugün ne var?']) {
        expect(find.widgetWithText(ActionChip, s), findsOneWidget, reason: s);
      }
      // Çip satırı yatay kaydırılır.
      final row = find.byKey(const ValueKey('quick-chips'));
      var seen = <String>{};
      for (var i = 0; i < 14 && seen.length < 3; i++) {
        for (final s in [
          'Bu ay ne kadar tahsilat?',
          'Gün sonu raporu',
          'Fiyat teklifi hazırla',
        ]) {
          if (find.widgetWithText(ActionChip, s).evaluate().isNotEmpty)
            seen = {...seen, s};
        }
        await t.drag(row, const Offset(-250, 0));
        await settle(t, 4);
      }
      for (final s in ['Fiyat teklifi hazırla']) {
        if (find.widgetWithText(ActionChip, s).evaluate().isNotEmpty)
          seen = {...seen, s};
      }
      expect(seen, {
        'Bu ay ne kadar tahsilat?',
        'Gün sonu raporu',
        'Fiyat teklifi hazırla',
      });
    });

    testWidgets('saha: para ve teklif çipleri yok', (t) async {
      await pumpScreen(t, const AssistantScreen(), role: UserRole.saha);
      await settle(t);
      expect(find.widgetWithText(ActionChip, 'Ödeme ekle'), findsNothing);
      expect(
        find.widgetWithText(ActionChip, 'Bu ay ne kadar tahsilat?'),
        findsNothing,
      );
      expect(
        find.widgetWithText(ActionChip, 'Fiyat teklifi hazırla'),
        findsNothing,
      );
      expect(find.byTooltip('Müdür önerileri'), findsNothing);
      expect(find.widgetWithText(ActionChip, 'Bugün ne var?'), findsOneWidget);
    });

    testWidgets('komut yaz → kullanıcı balonu ve yanıt', (t) async {
      await pumpScreen(t, const AssistantScreen());
      await settle(t);
      await _enter(t, 'Bugün ne var?');
      expect(find.text('Bugün ne var?'), findsWidgets);
      expect(find.textContaining('3 randevunuz var'), findsOneWidget);
    });

    testWidgets('çip: Randevu ekle komut çubuğunu doldurur', (t) async {
      await pumpScreen(t, const AssistantScreen());
      await settle(t);
      await t.tap(find.widgetWithText(ActionChip, 'Randevu ekle'));
      await t.pump();
      final field = t.widget<TextField>(find.byType(TextField).last);
      expect(field.controller!.text, startsWith('Randevu ekle'));
    });

    testWidgets('anlaşılmayan komut: "Ne demek istediniz?" kartı', (t) async {
      await pumpScreen(t, const AssistantScreen());
      await settle(t);
      await _enter(t, 'asdf qwer');
      expect(find.textContaining('Ne demek istediniz'), findsWidgets);
    });

    testWidgets('onay kartı: Onayla → uygulandı → Geri al', (t) async {
      await pumpScreen(t, const AssistantScreen());
      await settle(t);
      await _enter(t, 'Ödeme ekle');
      expect(find.text('Onayla'), findsOneWidget);
      expect(find.text('Vazgeç'), findsOneWidget);
      await t.tap(find.text('Onayla'));
      await settle(t);
      expect(find.text('Geri al'), findsOneWidget);
      await t.tap(find.text('Geri al'));
      await settle(t);
      expect(find.text('Geri al'), findsNothing);
    });

    testWidgets('mikrofon: paket yoksa klavye dikte ipucu', (t) async {
      await pumpScreen(t, const AssistantScreen());
      await settle(t);
      await t.tap(find.byTooltip('Sesle yaz'));
      await t.pump();
      expect(find.textContaining('mikrofon'), findsOneWidget);
    });
  });

  group('Brifing', () {
    testWidgets('yönetici: bölümler ve para özeti', (t) async {
      await pumpScreen(t, const BriefingScreen());
      await settle(t);
      expect(find.text('Bugünün randevuları'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Para özeti'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Para özeti'), findsOneWidget);
    });

    testWidgets('saha: para özeti ve yeni teklifler YOK', (t) async {
      await pumpScreen(t, const BriefingScreen(), role: UserRole.saha);
      await settle(t);
      expect(find.text('Bugünün randevuları'), findsOneWidget);
      expect(find.text('Para özeti'), findsNothing);
      expect(find.text('Yeni teklifler'), findsNothing);
      expect(find.text('Geciken tahsilatlar'), findsNothing);
    });
  });

  group('Müdür', () {
    testWidgets('yönetici: etiket, Neden? kanıtı', (t) async {
      await pumpScreen(t, const InsightsScreen());
      await settle(t);
      expect(find.textContaining('Önümüzdeki 7 günün'), findsOneWidget);
      expect(find.text('Uyarı'), findsWidgets);
      await t.tap(find.text('Neden?').first);
      await settle(t);
      expect(find.text('Kalan bakiye'), findsOneWidget);
      expect(find.text('₺12.450,55'), findsWidgets);
    });

    testWidgets('personel: kapalı', (t) async {
      await pumpScreen(t, const InsightsScreen(), role: UserRole.personel);
      await settle(t);
      expect(find.text('Bu bölüm sizin için kapalı'), findsOneWidget);
      expect(find.textContaining('Önümüzdeki 7 günün'), findsNothing);
    });

    testWidgets('Kapat: öneri listeden çıkar', (t) async {
      await pumpScreen(t, const InsightsScreen());
      await settle(t);
      expect(find.text('Kapat'), findsNWidgets(2));
      await t.tap(find.text('Kapat').first);
      await settle(t);
      expect(find.text('Kapat'), findsOneWidget);
    });

    testWidgets('kurallar: yalnız admin; bağımlılık durumu gösterilmez', (
      t,
    ) async {
      await pumpScreen(t, const InsightRulesScreen());
      await settle(t);
      expect(find.byType(Switch), findsWidgets);
      expect(find.textContaining('ağımlı'), findsNothing);
    });

    testWidgets('kurallar: muhasebe için yetki yok', (t) async {
      await pumpScreen(t, const InsightRulesScreen(), role: UserRole.muhasebe);
      await settle(t);
      expect(find.text('Yetkiniz yok'), findsOneWidget);
    });
  });

  group('Gün sonu', () {
    testWidgets('sorular tek dokunuşla; para sorusu tutar ister', (t) async {
      await pumpScreen(t, const ClosureScreen());
      await settle(t);
      expect(find.textContaining('nasıl geçti'), findsOneWidget);
      await t.tap(find.text('Ertelendi'));
      await settle(t);
      expect(find.textContaining('tahsilat ya da gider'), findsOneWidget);
      await t.tap(find.text('+ Tahsilat'));
      await settle(t);
      expect(find.byType(TextField), findsWidgets);
    });
  });

  group('Gelen kutusu ve tercihler', () {
    testWidgets('gelen kutusu listelenir, zil rozeti', (t) async {
      await pumpScreen(t, const InboxScreen());
      await settle(t);
      expect(find.text('Yeni teklif talebi'), findsOneWidget);
    });

    testWidgets('tercihler: açık/kapalı anahtarı', (t) async {
      await pumpScreen(t, const NotificationPrefsScreen());
      await settle(t);
      expect(find.byType(Switch), findsWidgets);
    });

    testWidgets('rızalar boş/dolu durumda çökmez', (t) async {
      await pumpScreen(t, const ConsentsScreen());
      await settle(t);
      expect(find.byType(ConsentsScreen), findsOneWidget);
    });
  });

  group('Yazışma önerileri', () {
    testWidgets('kaynak mesaj gösterilir; kabul edince satır kalkar', (
      t,
    ) async {
      await pumpScreen(t, const SuggestionsScreen());
      await settle(t);
      expect(find.textContaining('Kaynak mesaj'), findsWidgets);
      expect(find.textContaining('Balkon ölçüsü'), findsWidgets);
      await t.tap(find.text('Kabul et').first);
      await settle(t);
      expect(find.textContaining('Balkon ölçüsü'), findsNothing);
    });
  });
}
