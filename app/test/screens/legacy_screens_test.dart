// Eski panelde olan finans ekranlarının yeni uygulamada bulunduğunu doğrular
import 'package:flutter/widgets.dart' show Size;
// (Alacaklarım, proje bazlı kâr/zarar, Kullanıcılar menüsü).
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

void main() {
  testWidgets(
    'Alacaklarım: /finance/receivables açılır, Alacaklar başlığı var',
    (t) async {
      final h = await pumpXcApp(
        t,
        role: 'admin',
        initialLocation: '/finance/receivables',
      );
      expect(h.location, '/finance/receivables');
      expect(find.text('Alacaklar'), findsWidgets);
    },
  );

  testWidgets('Raporlar: proje bazlı kâr/zarar bölümü bulunur', (t) async {
    final h = await pumpXcApp(
      t,
      role: 'admin',
      initialLocation: '/reports',
      logicalSize: const Size(412, 4000),
    );
    await h.settle(20);
    expect(find.textContaining('kârlılığı'), findsWidgets);
  });
}
