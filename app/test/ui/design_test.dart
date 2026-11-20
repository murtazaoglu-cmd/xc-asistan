import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/theme/app_theme.dart';
import 'package:xc_asistan/core/theme/tokens.dart';
import 'package:xc_asistan/core/config/brand_profile.dart';
import 'package:xc_asistan/core/ui/ui.dart';

import 'ui_widgets_test.dart' show pumpUi;

void main() {
  group('tasarım değerleri (design-tokens.json)', () {
    test('açık palet', () {
      const s = AppPalette.lightScheme;
      expect(s.primary, const Color(0xFF3B82F6));
      expect(s.onSurface, const Color(0xFF172033));
      expect(s.surface, const Color(0xFFFFFFFF));
      expect(s.surfaceContainerLow, const Color(0xFFF5F7FB));
      expect(s.onSurfaceVariant, const Color(0xFF718096));
      expect(s.outlineVariant, const Color(0xFFE4E9F1));
      expect(s.error, const Color(0xFFEF4444));
      const x = AppPalette.lightExtras;
      expect(x.success, const Color(0xFF16A34A));
      expect(x.warning, const Color(0xFFF59E0B));
      expect(x.ai, const Color(0xFF8B5CF6));
      expect(x.navy, const Color(0xFF172033));
      expect(x.navySecondary, const Color(0xFF24324A));
      expect(x.assistant, const Color(0xFF3B82F6));
    });
    test('koyu palet', () {
      const s = AppPalette.darkScheme;
      expect(s.primary, const Color(0xFF60A5FA));
      expect(s.surfaceContainerLowest, const Color(0xFF0B1324));
      expect(s.surface, const Color(0xFF1E2938));
      expect(s.surfaceContainerHigh, const Color(0xFF334155));
      const x = AppPalette.darkExtras;
      expect(x.success, const Color(0xFF22C55E));
      expect(x.warning, const Color(0xFFFBBF24));
      expect(s.error, const Color(0xFFF87171));
      expect(x.ai, const Color(0xFFA78BFA));
    });
    test('boşluk, köşe, boyut, yazı', () {
      expect(
        [Space.xs, Space.sm, Space.md, Space.lg, Space.xl, Space.xxl],
        [4, 8, 12, 16, 24, 32],
      );
      expect(
        [
          Radii.xs,
          Radii.sm,
          Radii.md,
          Radii.lg,
          Radii.card,
          Radii.xl,
          Radii.xxl,
        ],
        [8, 10, 12, 16, 18, 22, 24],
      );
      expect(Sizes.minTouch, 48);
      expect(TypeTokens.body, 16);
      expect(TypeTokens.fontFamily, 'Inter');
    });
    test('tema: Inter, 48 dp düğme, marka rengi aşağı akar', () {
      final t = AppTheme.light();
      expect(t.textTheme.bodyLarge!.fontFamily, 'Inter');
      expect(t.scaffoldBackgroundColor, const Color(0xFFF5F7FB));
      expect(AppTheme.dark().scaffoldBackgroundColor, const Color(0xFF0B1324));
      final b = AppTheme.light(primary: const Color(0xFF008060));
      expect(b.colorScheme.primary, const Color(0xFF008060));
      expect(b.extension<XcColors>()!.assistant, const Color(0xFF008060));
    });
    test(
      'Türkçe karakterler Inter\'da var: tüm harfler yüklenebilir metin',
      () {
        const tr = 'ÇĞİÖŞÜ çğıöşü ₺ İstanbul';
        expect(tr.runes.length, greaterThan(10));
      },
    );
  });

  group('asistan kartları ve sayı kutusu', () {
    testWidgets('AiCard türleri etiket + eylem + Neden? gösterir', (t) async {
      var why = 0, ok = 0;
      await pumpUi(
        t,
        SingleChildScrollView(
          child: Column(
            children: [
              AiCard(kind: AiCardKind.summary, title: 'Bugün 3 randevu var'),
              AiCard(
                kind: AiCardKind.managerTip,
                title: 'Bu ay gider geliri geçti',
                body: 'Gider ₺210.000',
                onWhy: () => why++,
                actions: [
                  AiCardAction('İncele', () => ok++, primary: true),
                  AiCardAction('Sonra', () {}),
                ],
              ),
              const AiCard(
                kind: AiCardKind.confirm,
                title: 'Randevu eklensin mi?',
              ),
              const AiCard(kind: AiCardKind.noteSuggestion, title: 'Not öner'),
              const AiCard(
                kind: AiCardKind.draftReply,
                title: 'Taslak',
                child: Text('Merhaba'),
              ),
            ],
          ),
        ),
      );
      expect(find.text('Asistan Özeti'), findsOneWidget);
      expect(find.text('Uyarı'), findsOneWidget);
      expect(find.text('Müdür önerisi'), findsOneWidget);
      expect(find.text('Onay'), findsOneWidget);
      expect(find.text('Not önerisi'), findsOneWidget);
      expect(find.text('Taslak yanıt'), findsOneWidget);
      await t.tap(find.text('Neden?'));
      await t.tap(find.text('İncele'));
      expect(why, 1);
      expect(ok, 1);
    });

    testWidgets('StatTile değer, etiket ve dokunma hedefi', (t) async {
      var n = 0;
      await pumpUi(
        t,
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Randevu',
                value: '3',
                icon: Icons.event,
                onTap: () => n++,
              ),
            ),
            const Expanded(
              child: StatTile(
                label: 'Geciken iş',
                value: '2',
                icon: Icons.warning_amber,
              ),
            ),
          ],
        ),
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Geciken iş'), findsOneWidget);
      expect(
        t.getSize(find.byType(StatTile).first).height,
        greaterThanOrEqualTo(48),
      );
      await t.tap(find.text('Randevu'));
      expect(n, 1);
    });

    testWidgets('BrandLogo çizilir (çarpı işareti), çökmez', (t) async {
      await pumpUi(t, const BrandLogo(size: 64));
      expect(t.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
