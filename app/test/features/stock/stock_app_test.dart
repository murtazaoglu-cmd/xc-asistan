import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  testWidgets('admin: stok listesi, +1, düzenleme ve /stock/new rotaları', (
    t,
  ) async {
    final h = await pumpXcApp(t, role: 'admin', initialLocation: '/stock');
    expect(find.text('Profil 40x40'), findsOneWidget);
    expect(find.text('Düşük stok (2)'), findsOneWidget); // Profil + Boya
    await t.tap(find.byTooltip('Profil 40x40 artır'));
    await t.pump(const Duration(milliseconds: 700));
    await h.settle(20);
    expect(find.text('Düşük stok (2)'), findsOneWidget); // 3 hâlâ ≤ 5
    await t.tap(find.text('Profil 40x40'));
    await h.settle(20);
    expect(h.location, '/stock/mat-1');
    expect(find.text('Malzemeyi düzenle'), findsOneWidget);
    await h.go('/stock/new');
    expect(find.text('Yeni malzeme'), findsOneWidget);
  });

  testWidgets('personel yönlendirme korumasıyla Bugün\'e döner', (t) async {
    final h = await pumpXcApp(t, role: 'personel');
    await h.go('/stock');
    expect(h.location, '/today');
  });
}
