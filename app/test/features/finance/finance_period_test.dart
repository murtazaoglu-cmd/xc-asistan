// Tarih aralığı, yöntem/sahip süzgeçleri, Ev/Dükkan/İşletme kırılımı, owner_id, "kim ne kadar aldı".
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/finance/data/finance_calc.dart';
import 'package:xc_asistan/features/finance/data/finance_models.dart';
import 'package:xc_asistan/features/finance/data/finance_period.dart';
import 'package:xc_asistan/features/finance/data/finance_providers.dart';
import 'package:xc_asistan/features/finance/data/finance_repository.dart';
import 'package:xc_asistan/features/finance/presentation/expenses_tab.dart';
import 'package:xc_asistan/features/finance/presentation/payments_tab.dart';

import '../../helpers/fakes.dart';

Payment pay(
  String id,
  double tl,
  DateTime at, {
  String method = 'Havale',
  String? owner,
}) => Payment(
  id: id,
  projectId: 'x',
  amount: Money.fromTl(tl),
  method: method,
  paidAt: at,
  ownerId: owner,
);

Expense exp(String id, double tl, String scope, DateTime at, {String? owner}) =>
    Expense(
      id: id,
      category: 'K',
      amount: Money.fromTl(tl),
      scopeRaw: scope,
      expenseDate: at,
      ownerId: owner,
    );

void main() {
  setUp(() => Ist.clock = () => DateTime.utc(2026, 11, 20, 8));
  tearDown(() => Ist.clock = DateTime.now);

  group('FinancePeriod', () {
    test('ay: İstanbul ay sınırları ve etiket', () {
      final p = FinancePeriod.month(const YearMonth(2026, 11));
      expect(p.isCustom, isFalse);
      expect(p.label, 'Kasım 2026');
      expect(p.range.start, DateTime.utc(2026, 10, 31, 21));
      expect(p.range.end, DateTime.utc(2026, 11, 30, 21));
    });

    test('serbest aralık: bitiş günü DAHİL (İstanbul 23:59 içeride, ertesi gün 00:00 dışarıda)', () {
      final p = FinancePeriod.custom(
        Ist.fromWall(2026, 11, 10),
        Ist.fromWall(2026, 11, 15),
      );
      expect(p.isCustom, isTrue);
      expect(p.label, '10 Kas – 15 Kas 2026');
      expect(p.contains(Ist.fromWall(2026, 11, 10)), isTrue);
      expect(p.contains(Ist.fromWall(2026, 11, 15, 23, 59)), isTrue);
      expect(p.contains(Ist.fromWall(2026, 11, 16)), isFalse);
      expect(p.contains(Ist.fromWall(2026, 11, 9, 23, 59)), isFalse);
      expect(p.endMonth, const YearMonth(2026, 11));
    });

    test('ters sıra düzeltilir; tek gün; yıl aşan etiket', () {
      final r = FinancePeriod.custom(
        Ist.fromWall(2026, 11, 15),
        Ist.fromWall(2026, 11, 10),
      );
      expect(r.label, '10 Kas – 15 Kas 2026');
      final one = FinancePeriod.custom(
        Ist.fromWall(2026, 11, 3),
        Ist.fromWall(2026, 11, 3),
      );
      expect(one.label, '3 Kas 2026');
      expect(one.contains(Ist.fromWall(2026, 11, 3, 12)), isTrue);
      final cross = FinancePeriod.custom(
        Ist.fromWall(2025, 12, 20),
        Ist.fromWall(2026, 1, 5),
      );
      expect(cross.label, '20 Ara 2025 – 5 Oca 2026');
      expect(cross.endMonth, const YearMonth(2026, 1));
    });

    test(
      'CustomPeriodNotifier: gelecek bugüne kırpılır, clear ay seçiciye döner',
      () {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        expect(c.read(activePeriodProvider).isCustom, isFalse);
        c
            .read(customPeriodProvider.notifier)
            .setRange(Ist.fromWall(2026, 11, 10), Ist.fromWall(2027, 3, 1));
        final p = c.read(activePeriodProvider);
        expect(p.isCustom, isTrue);
        expect(p.range.end, Ist.fromWall(2026, 11, 21)); // bugün (20 Kas) dahil
        c.read(customPeriodProvider.notifier).clear();
        expect(c.read(activePeriodProvider).label, 'Kasım 2026');
      },
    );
  });

  group('FinanceCalc: aralık toplamı ve kırılım', () {
    final range = FinancePeriod.custom(
      Ist.fromWall(2026, 11, 10),
      Ist.fromWall(2026, 11, 15),
    ).range;
    final inside = DateTime.utc(2026, 11, 12, 9);
    final edgeLast = Ist.fromWall(2026, 11, 15, 23, 30);
    final outside = Ist.fromWall(2026, 11, 16, 0, 10);

    test('totalsForRange: aralık dışı sayılmaz; kâr/zarar', () {
      final t = FinanceCalc.totalsForRange(
        [
          pay('a', 1000, inside),
          pay('b', 500, edgeLast),
          pay('c', 9999, outside),
        ],
        [
          exp('d', 400, 'dukkan', inside),
          exp('e', 2000, 'genel', edgeLast),
          exp('f', 700, 'ev', inside),
        ],
        range,
      );
      expect(t.revenue, Money.fromTl(1500));
      expect(t.businessExpense, Money.fromTl(2400));
      expect(t.personalExpense, Money.fromTl(700));
      expect(t.profit, Money.fromTl(-900)); // zarar
      expect(t.profit.isNegative, isTrue);
    });

    test('breakdownForRange: Ev / Dükkan / İşletme ayrı', () {
      final b = FinanceCalc.breakdownForRange([
        exp('1', 100, 'ev', inside),
        exp('2', 200, 'dukkan', inside),
        exp('3', 300, 'genel', inside),
        exp('4', 50, 'genel', inside),
        exp('5', 999, 'ev', outside),
      ], range);
      expect(b.home, Money.fromTl(100));
      expect(b.shop, Money.fromTl(200));
      expect(b.business, Money.fromTl(350));
      expect(b.businessTotal, Money.fromTl(550));
    });

    test('byOwner: sahibe göre toplam, büyükten küçüğe; sahibi olmayan null altında', () {
      final l = FinanceCalc.byOwner([
        pay('1', 100, inside, owner: 'ali'),
        pay('2', 900, inside, owner: 'veli'),
        pay('3', 50, inside, owner: 'ali'),
        pay('4', 10, inside),
      ]);
      expect(l.map((e) => e.ownerId), ['veli', 'ali', null]);
      expect(l.first.total, Money.fromTl(900));
      expect(l[1].total, Money.fromTl(150));
      expect(l[1].count, 2);
    });
  });

  group('Süzgeçler', () {
    final range = FinancePeriod.month(const YearMonth(2026, 11)).range;
    final d = DateTime.utc(2026, 11, 12, 9);
    final all = [
      pay('1', 100, d, method: 'Havale', owner: 'a'),
      pay(
        '2',
        200,
        d.add(const Duration(days: 1)),
        method: 'Nakit',
        owner: 'b',
      ),
      pay('3', 300, d.add(const Duration(days: 2)), method: 'Nakit'),
      pay('4', 400, DateTime.utc(2026, 10, 1), method: 'Nakit', owner: 'a'),
    ];

    test('paymentsInRange: yöntem + sahip + dönem + gizli', () {
      expect(paymentsInRange(all, range, {}).map((e) => e.id), ['3', '2', '1']);
      expect(
        paymentsInRange(all, range, {}, method: 'Nakit').map((e) => e.id),
        ['3', '2'],
      );
      expect(paymentsInRange(all, range, {}, ownerId: 'a').map((e) => e.id), [
        '1',
      ]);
      expect(paymentsInRange(all, range, {}, ownerId: '').map((e) => e.id), [
        '3',
      ]);
      expect(
        paymentsInRange(
          all,
          range,
          {},
          method: 'Nakit',
          ownerId: 'b',
        ).map((e) => e.id),
        ['2'],
      );
      expect(paymentsInRange(all, range, {'3'}).map((e) => e.id), ['2', '1']);
      expect(paymentsOfMonth(all, const YearMonth(2026, 11), {}).length, 3);
    });

    test('expensesInRange: Ev/Dükkan/İşletme süzgeci, ev yetkisizse gizli', () {
      final ex = [
        exp('1', 1, 'ev', d),
        exp('2', 2, 'dukkan', d),
        exp('3', 3, 'genel', d),
      ];
      expect(
        expensesInRange(
          ex,
          range,
          {},
          filter: ExpenseFilter.home,
        ).map((e) => e.id),
        ['1'],
      );
      expect(
        expensesInRange(
          ex,
          range,
          {},
          filter: ExpenseFilter.shop,
        ).map((e) => e.id),
        ['2'],
      );
      expect(
        expensesInRange(
          ex,
          range,
          {},
          filter: ExpenseFilter.business,
        ).map((e) => e.id),
        ['3'],
      );
      expect(
        expensesInRange(
          ex,
          range,
          {},
          allowPersonal: false,
        ).map((e) => e.id).toSet(),
        {'2', '3'},
      );
      expect(
        [for (final f in ExpenseFilter.values) f.label],
        ['Tümü', 'Ev', 'Dükkan', 'İşletme'],
      );
    });
  });

  group('Kapsam etiketleri (eski panel uyumu)', () {
    test('sunucu değerleri ↔ görünen adlar', () {
      expect(ScopeView.fromApi('ev').label, 'Ev');
      expect(ScopeView.fromApi('dukkan').label, 'Dükkan');
      expect(ScopeView.fromApi('genel').label, 'İşletme');
      expect(
        [for (final s in ScopeView.values) s.groupLabel],
        ['Ev Giderleri', 'Dükkan Giderleri', 'İşletme Giderleri'],
      );
      // Sunucuya giden değerler değişmedi.
      expect(
        [for (final s in ScopeView.values) s.api],
        ['ev', 'dukkan', 'genel'],
      );
    });
  });

  group('owner_id gövdesi', () {
    test('PaymentInput: yalnız doluysa gönderilir', () {
      final a = PaymentInput(
        amount: Money.fromTl(10),
        method: 'Nakit',
        paidAt: DateTime.utc(2026, 11, 20),
      );
      expect(a.toJson().containsKey('owner_id'), isFalse);
      final b = PaymentInput(
        amount: Money.fromTl(10),
        method: 'Nakit',
        paidAt: DateTime.utc(2026, 11, 20),
        ownerId: 'u-1',
      );
      expect(b.toJson()['owner_id'], 'u-1');
    });
    test('ExpenseInput: oluşturma ve düzenlemede', () {
      final e = ExpenseInput(
        category: 'Yakıt',
        amount: Money.fromTl(10),
        scope: ScopeView.general,
        date: DateTime.utc(2026, 11, 20),
        ownerId: 'u-2',
      );
      expect(e.toCreateJson()['owner_id'], 'u-2');
      expect(e.toPatchJson()['owner_id'], 'u-2');
      final n = ExpenseInput(
        category: 'Yakıt',
        amount: Money.fromTl(10),
        scope: ScopeView.general,
        date: DateTime.utc(2026, 11, 20),
      );
      expect(n.toCreateJson().containsKey('owner_id'), isFalse);
      expect(n.toPatchJson().containsKey('owner_id'), isFalse);
    });
  });

  group('OwnerDirectory', () {
    const dir = OwnerDirectory(
      selfId: 'me',
      names: {'me': 'Ayşe', 'u2': 'Veli'},
    );
    test('adlar; ham UUID gösterilmez', () {
      expect(dir.nameOf('me'), 'Ayşe (Ben)');
      expect(dir.nameOf('u2'), 'Veli');
      expect(dir.nameOf('00000000-aaaa'), 'Başka kullanıcı');
      expect(dir.nameOf(null), 'Sahibi belirtilmemiş');
      expect(dir.otherOwnerName('me'), isNull);
      expect(dir.otherOwnerName('u2'), 'Veli');
      expect(dir.otherOwnerName(null), isNull);
    });
  });

  group('projectPeople', () {
    HttpFinanceRepository repo(ScriptedAdapter a) => HttpFinanceRepository(
      ApiClient(
        Dio(BaseOptions(baseUrl: 'https://api.test/api'))
          ..httpClientAdapter = a,
      ),
    );

    test('GET /projects/:id/collaborators → OwnerRef', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(200, [
          {'id': 'u1', 'name': 'Ali', 'role': 'personel'},
          {'id': '', 'name': 'Boş'},
        ]),
      );
      final l = await repo(a).projectPeople('prj-1');
      expect(a.requests.single.path, '/projects/prj-1/collaborators');
      expect(l.map((e) => e.name), ['Ali']);
    });

    test('403/404 → boş liste; ağ hatası yukarı çıkar', () async {
      for (final c in [403, 404]) {
        final a = ScriptedAdapter(
          (i, o) => ScriptedResponse(c, {'error': 'x'}),
        );
        expect(await repo(a).projectPeople('p'), isEmpty);
      }
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(400, {'error': 'x'}),
      );
      await expectLater(
        repo(a).projectPeople('p'),
        throwsA(isA<AppException>()),
      );
    });

    test('ödeme oluşturma gövdesi owner_id taşır', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(201, {
          'id': 'p',
          'project_id': 'prj',
          'amount': 10,
          'method': 'Nakit',
        }),
      );
      await repo(a).createPayment(
        'prj',
        PaymentInput(
          amount: Money.fromTl(10),
          method: 'Nakit',
          paidAt: DateTime.utc(2026, 11, 20),
          ownerId: 'u-9',
        ),
      );
      expect((a.requests.single.data as Map)['owner_id'], 'u-9');
    });
  });
}
