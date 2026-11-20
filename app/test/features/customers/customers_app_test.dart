// Gerçek uygulama + DEMO API ile uçtan uca gezinme (rota sırası, yetki koruması).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/app_harness.dart';

void main() {
  testWidgets('admin: liste → kart → düzenle formu; /customers/new form açar', (
    t,
  ) async {
    final h = await pumpXcApp(t, role: 'admin', initialLocation: '/customers');
    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('A'), findsWidgets); // harf başlığı
    await t.tap(find.text('Ayşe Yılmaz'));
    await h.settle(20);
    expect(h.location, '/customers/05321112233');
    await t.scrollUntilVisible(
      find.text('Yazışmalar ve notlar'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Yazışmalar ve notlar'), findsOneWidget);
    await t.tap(find.byTooltip('Düzenle'));
    await h.settle(20);
    expect(h.location, '/customers/05321112233/edit');
    expect(find.text('Müşteri düzenle'), findsOneWidget);
    await h.go('/customers/new');
    expect(
      find.text('Yeni müşteri'),
      findsOneWidget,
    ); // ":phoneKey" yerine form
  });

  testWidgets('demo: yeni müşteri ekle → karta gider', (t) async {
    final h = await pumpXcApp(
      t,
      role: 'admin',
      initialLocation: '/customers/new',
    );
    await t.enterText(find.byKey(const Key('field-name')), 'Deneme Kişi');
    await t.enterText(find.byKey(const Key('field-phone')), '0555 123 45 67');
    await t.pump(const Duration(milliseconds: 600));
    await h.settle(10);
    await t.tap(find.text('Müşteri ekle'));
    await h.settle(30);
    expect(h.location, '/customers/05551234567');
    expect(find.text('Deneme Kişi'), findsWidgets);
  });

  testWidgets('personel: /customers yönlendirme korumasıyla Bugün\'e döner', (
    t,
  ) async {
    final h = await pumpXcApp(t, role: 'personel');
    await h.go('/customers');
    expect(h.location, '/today');
  });
}
