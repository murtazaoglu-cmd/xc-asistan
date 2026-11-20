import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/app_harness.dart';

void main() {
  testWidgets(
    'admin: raporlar DEMO veriyle yüklenir; grafik ve ev gideri ayrımı',
    (t) async {
      final h = await pumpXcApp(t, role: 'admin', initialLocation: '/reports');
      await h.settle(30);
      expect(find.text('Raporlar'), findsWidgets);
      expect(find.text('Genel durum'), findsOneWidget);
      expect(find.text('Ev giderleri (kâra dahil değil)'), findsWidgets);
      await t.scrollUntilVisible(
        find.text('Gelir ve gider'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Gelir ve gider'), findsOneWidget);
      expect(find.text('Aylık'), findsOneWidget);
    },
  );
}
