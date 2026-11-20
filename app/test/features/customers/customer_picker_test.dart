import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/customers/customers_public.dart';
import 'package:xc_asistan/features/customers/data/customers_repository.dart';
import 'package:xc_asistan/features/customers/presentation/customers_screen.dart';

import '../../helpers/fakes.dart';
import 'harness.dart';

Map<String, dynamic> row(
  String key,
  String name, {
  num contracted = 0,
  num paid = 0,
  int offers = 1,
  int projects = 0,
}) => {
  'phone_key': key,
  'name': name,
  'phone': key,
  'region': 'Bodrum',
  'offer_count': offers,
  'project_count': projects,
  'total_contracted': contracted,
  'total_paid': paid,
};

void main() {
  testWidgets('seçici: arar, sonucu seçince Customer döner', (t) async {
    final a = ScriptedAdapter((i, o) {
      final q = o.queryParameters['q'] as String?;
      final rows = [
        row('05321112233', 'Ayşe Yılmaz'),
        row('05329998877', 'Burak Aydın'),
      ];
      return ScriptedResponse(200, [
        for (final r in rows)
          if (q == null ||
              (r['name'] as String).toLowerCase().contains(q.toLowerCase()))
            r,
      ]);
    });
    Customer? picked;
    await pumpScreen(
      t,
      Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await showCustomerPicker(ctx),
            child: const Text('aç'),
          ),
        ),
      ),
      overrides: [
        customersRepositoryProvider.overrideWithValue(
          HttpCustomersRepository(apiWith(a)),
        ),
      ],
    );
    await t.tap(find.text('aç'));
    await settle(t);
    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('Burak Aydın'), findsOneWidget);
    await t.enterText(find.byKey(const Key('customer-picker-search')), 'burak');
    await t.pump(const Duration(milliseconds: 400));
    await settle(t);
    expect(find.text('Ayşe Yılmaz'), findsNothing);
    expect(a.requests.last.queryParameters['q'], 'burak');
    await t.tap(find.text('Burak Aydın'));
    await settle(t);
    expect(picked?.phoneKey, '05329998877');
  });

  testWidgets('seçici: sonuç yoksa boş durum; hata → Tekrar dene', (t) async {
    var fail = true;
    final a = ScriptedAdapter(
      (i, o) => fail
          ? ScriptedResponse(500, {'error': 'x'})
          : ScriptedResponse(200, <dynamic>[]),
    );
    await pumpScreen(
      t,
      Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showCustomerPicker(ctx),
            child: const Text('aç'),
          ),
        ),
      ),
      overrides: [
        customersRepositoryProvider.overrideWithValue(
          HttpCustomersRepository(apiWith(a)),
        ),
      ],
    );
    await t.tap(find.text('aç'));
    await settle(t, 20);
    expect(find.text('Tekrar dene'), findsOneWidget);
    fail = false;
    await t.tap(find.text('Tekrar dene'));
    await settle(t, 20);
    expect(find.text('Müşteri bulunamadı'), findsOneWidget);
  });

  testWidgets('liste satırı: sözleşme ve ödenen özeti + bölge', (t) async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(
        200,
        [
          row(
            '05321112233',
            'Ayşe Yılmaz',
            contracted: 20000,
            paid: 5000,
            projects: 1,
            offers: 2,
          ),
          row('05329998877', 'Burak Aydın'),
        ],
        {'x-total-count': '2'},
      ),
    );
    await pumpScreen(
      t,
      const CustomersScreen(),
      overrides: [
        customersRepositoryProvider.overrideWithValue(
          HttpCustomersRepository(apiWith(a)),
        ),
      ],
    );
    await settle(t, 15);
    expect(find.textContaining('Bodrum'), findsNWidgets(2));
    final money = find.byKey(const Key('customer-money'));
    expect(money, findsOneWidget); // yalnız sözleşmesi olan satırda
    final text = t.widget<Text>(money).data!;
    expect(
      text,
      contains('Sözleşme ${Money.fromTl(20000).format(hideZeroKurus: true)}'),
    );
    expect(
      text,
      contains('Ödenen ${Money.fromTl(5000).format(hideZeroKurus: true)}'),
    );
    expect(text, contains('2 fiyat teklifi'));
  });
}
