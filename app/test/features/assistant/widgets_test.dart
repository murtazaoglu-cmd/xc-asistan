import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/features/assistant/presentation/briefing_summary_card.dart';
import 'package:xc_asistan/features/assistant/presentation/inbox_screen.dart';

import 'harness.dart';

void main() {
  group('BriefingSummaryCard (Bugün ekranına takılır)', () {
    testWidgets('mor "Asistan Özeti" kartı, sayı karoları, dokununca brifing', (
      t,
    ) async {
      final router = await pumpScreen(
        t,
        const Scaffold(body: BriefingSummaryCard()),
      );
      await settle(t);
      expect(find.text('Asistan Özeti'), findsOneWidget);
      expect(find.text('Randevu'), findsOneWidget);
      await t.tap(find.text('Brifingi aç'));
      await settle(t);
      expect(router.state.uri.path, '/assistant/briefing');
    });

    testWidgets('onOpen verilirse onu çağırır', (t) async {
      var opened = 0;
      await pumpScreen(
        t,
        Scaffold(body: BriefingSummaryCard(onOpen: () => opened++)),
      );
      await settle(t);
      await t.tap(find.text('Brifingi aç'));
      expect(opened, 1);
    });

    testWidgets('saha: para ve teklif karoları yok', (t) async {
      await pumpScreen(
        t,
        const Scaffold(body: BriefingSummaryCard()),
        role: UserRole.saha,
      );
      await settle(t);
      expect(find.text('Randevu'), findsOneWidget);
      expect(find.text('Tahsilat'), findsNothing);
      expect(find.text('Fiyat teklifi'), findsNothing);
    });
  });

  testWidgets('zil düğmesi okunmamış sayısını rozetle gösterir', (t) async {
    await pumpScreen(t, const Scaffold(body: Center(child: InboxBellButton())));
    await settle(t);
    expect(
      find.byWidgetPredicate(
        (w) => w is IconButton && (w.tooltip ?? '').contains('okunmamış'),
      ),
      findsOneWidget,
    );
  });
}
