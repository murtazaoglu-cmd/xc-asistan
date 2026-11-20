import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/demo/demo_adapter.dart';
import 'package:xc_asistan/core/demo/demo_db.dart';
import 'package:xc_asistan/features/stock/data/stock_models.dart';
import 'package:xc_asistan/features/stock/data/stock_repository.dart';

import '../../helpers/fakes.dart';
import 'harness.dart';

Map<String, dynamic> mat(String id, String name, num q, num min) => {
  'id': id,
  'name': name,
  'unit': 'adet',
  'stock_quantity': q,
  'low_stock_threshold': min,
  'note': null,
  'updated_at': '2026-11-19T09:00:00.000Z',
  'owner_id': 'u1',
};

class FakeStockRepo implements StockRepository {
  FakeStockRepo(this.items);
  List<StockItem> items;
  final List<(String, double)> writes = [];
  Object? writeError;

  @override
  Future<List<StockItem>> list() async => items;
  @override
  Future<StockItem> create(StockInput input) async => items.first;
  @override
  Future<StockItem> update(String id, StockInput input) async => items.first;
  @override
  Future<void> setQuantity(String id, double q) async {
    writes.add((id, q));
    if (writeError != null) throw writeError!;
  }

  @override
  Future<void> delete(String id) async {}
}

void main() {
  group('StockItem', () {
    test('sözleşme satırı; düşük stok quantity ≤ eşik', () {
      final i = StockItem.fromJson(mat('m1', 'Boya', 4, 5));
      expect(i.quantity, 4);
      expect(i.minStock, 5);
      expect(i.isLow, isTrue);
      expect(i.isOut, isFalse);
      expect(
        StockItem.fromJson(mat('m', 'x', 5, 5)).isLow,
        isTrue,
      ); // eşitlik düşük
      expect(StockItem.fromJson(mat('m', 'x', 6, 5)).isLow, isFalse);
      expect(StockItem.fromJson(mat('m', 'x', 0, 5)).isOut, isTrue);
    });

    test('NUMERIC metin olarak gelirse ve eksik alanlarda çökmez', () {
      final i = StockItem.fromJson({
        'id': 'a',
        'name': 'Kablo',
        'stock_quantity': '12.50',
        'low_stock_threshold': '2.5',
      });
      expect(i.quantity, 12.5);
      expect(i.minStock, 2.5);
      expect(i.unit, 'adet');
      final empty = StockItem.fromJson({});
      expect(empty.name, '');
      expect(empty.quantity, 0);
      // min_stock adıyla gelen alan
      expect(StockItem.fromJson({'min_stock': 7}).minStock, 7);
    });
  });

  group('StockQty', () {
    test('biçim: tam sayı ondalıksız, Türkçe virgül', () {
      expect(StockQty.format(12), '12');
      expect(StockQty.format(2.5), '2,5');
      expect(StockQty.format(0.125), '0,125');
      expect(StockQty.format(0.1 + 0.2), '0,3');
    });

    test('ayrıştırma: virgül/nokta/bin ayracı; negatif ve çöp reddedilir', () {
      expect(StockQty.parse('12'), 12);
      expect(StockQty.parse('12,5'), 12.5);
      expect(StockQty.parse('12.5'), 12.5);
      expect(StockQty.parse('1.250'), 1250);
      expect(StockQty.parse(' 3 '), 3);
      expect(StockQty.parse('-1'), isNull);
      expect(StockQty.parse('abc'), isNull);
      expect(StockQty.parse(''), isNull);
      expect(StockQty.parse('1,2,3'), isNull);
      expect(StockQty.parse('2000000000'), isNull);
    });

    test('toJson: tam sayı int, ondalık num', () {
      expect(StockQty.toJson(4), isA<int>());
      expect(StockQty.toJson(4.5), 4.5);
    });
  });

  group('Form doğrulama', () {
    test('ad zorunlu', () {
      expect(StockValidators.name(' '), isNotNull);
      expect(StockValidators.name('Boya'), isNull);
    });
    test('miktar negatif olamaz', () {
      expect(StockValidators.quantity(''), 'Miktar girin.');
      expect(StockValidators.quantity('-2'), isNotNull);
      expect(StockValidators.quantity('0'), isNull);
      expect(StockValidators.quantity('2,5'), isNull);
      expect(
        StockValidators.quantity('x', field: 'Asgari stok'),
        contains('Asgari stok'),
      );
    });
    test('girdi → POST/PATCH gövdesi', () {
      const input = StockInput(
        name: ' Vida ',
        unit: '',
        quantity: 3,
        minStock: 2.5,
        note: '',
      );
      expect(input.toJson(), {
        'name': 'Vida',
        'unit': 'adet',
        'stock_quantity': 3,
        'low_stock_threshold': 2.5,
        'note': null,
      });
    });
  });

  group('Arama, süzgeç, sıralama', () {
    final items = [
      StockItem.fromJson(mat('1', 'Çivi', 50, 10)),
      StockItem.fromJson(mat('2', 'Boya', 4, 5)),
      StockItem.fromJson(mat('3', 'Vida', 0, 5)),
      StockItem.fromJson(mat('4', 'Akü', 9, 5)),
    ];
    test('düşük stok önce, sonra Türkçe alfabetik', () {
      expect(filterStock(items).map((e) => e.name), [
        'Boya',
        'Vida',
        'Akü',
        'Çivi',
      ]);
    });
    test('yalnız düşük + arama', () {
      expect(filterStock(items, onlyLow: true).map((e) => e.name), [
        'Boya',
        'Vida',
      ]);
      expect(filterStock(items, query: 'çiv').map((e) => e.name), ['Çivi']);
      expect(filterStock(items, query: 'bo').map((e) => e.name), ['Boya']);
    });
  });

  group('Repository (sahte Dio)', () {
    test(
      'list / create / PATCH stok ± yalnız stock_quantity / delete',
      () async {
        final a = ScriptedAdapter((i, o) {
          switch (i) {
            case 0:
              return ScriptedResponse(200, [mat('m1', 'Boya', 4, 5)]);
            case 1:
              return ScriptedResponse(201, mat('m2', 'Vida', 10, 5));
            default:
              return ScriptedResponse(200, {'message': 'ok'});
          }
        });
        final repo = HttpStockRepository(apiWith(a));
        expect((await repo.list()).single.name, 'Boya');
        expect(a.requests[0].path, '/materials');
        final created = await repo.create(
          const StockInput(name: 'Vida', quantity: 10),
        );
        expect(created.id, 'm2');
        expect(a.requests[1].method, 'POST');
        expect((a.requests[1].data as Map)['low_stock_threshold'], 5);
        await repo.setQuantity('m1', 7);
        expect(a.requests[2].method, 'PATCH');
        expect(a.requests[2].path, '/materials/m1');
        expect(a.requests[2].data, {'stock_quantity': 7});
        await repo.delete('m1');
        expect(a.requests[3].method, 'DELETE');
      },
    );

    test('403 → forbidden; 400 → validation', () async {
      final a = ScriptedAdapter(
        (i, o) => i == 0
            ? ScriptedResponse(403, {'error': 'Bu işlem için yetkiniz yok.'})
            : ScriptedResponse(400, {
                'error': 'Geçersiz veya eksik değer girildi.',
              }),
      );
      final repo = HttpStockRepository(apiWith(a));
      await expectLater(
        repo.list(),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'c',
            AppErrorCode.forbidden,
          ),
        ),
      );
      await expectLater(
        repo.setQuantity('m', 1),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'c',
            AppErrorCode.validation,
          ),
        ),
      );
    });
  });

  group('Hızlı +/- (iyimser, birleştirilmiş yazma)', () {
    late Duration saved;
    setUp(() {
      saved = StockListNotifier.debounce;
      StockListNotifier.debounce = const Duration(milliseconds: 30);
    });
    tearDown(() => StockListNotifier.debounce = saved);

    ProviderContainer make(FakeStockRepo repo) {
      final c = ProviderContainer(
        overrides: [stockRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      c.listen(stockListProvider, (_, _) {});
      return c;
    }

    test('art arda üç dokunuş tek PATCH olur, anında ekrana yansır', () async {
      final repo = FakeStockRepo([StockItem.fromJson(mat('m1', 'Boya', 4, 5))]);
      final c = make(repo);
      await c.read(stockListProvider.future);
      final n = c.read(stockListProvider.notifier);
      n.adjust('m1', 1);
      n.adjust('m1', 1);
      n.adjust('m1', 1);
      expect(c.read(stockListProvider).value!.items.single.quantity, 7);
      expect(c.read(stockListProvider).value!.saving, {'m1'});
      expect(repo.writes, isEmpty, reason: 'bekleme dolmadan yazılmaz');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(repo.writes, [('m1', 7.0)]);
      expect(c.read(stockListProvider).value!.saving, isEmpty);
    });

    test('0 altına inmez; ondalık birikim yok', () async {
      final repo = FakeStockRepo([
        StockItem.fromJson(mat('m1', 'Boya', 0.1, 5)),
      ]);
      final c = make(repo);
      await c.read(stockListProvider.future);
      final n = c.read(stockListProvider.notifier);
      n.adjust('m1', 0.2);
      expect(c.read(stockListProvider).value!.items.single.quantity, 0.3);
      n.adjust('m1', -5);
      expect(c.read(stockListProvider).value!.items.single.quantity, 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    test('değer girişi hemen yazılır', () async {
      final repo = FakeStockRepo([StockItem.fromJson(mat('m1', 'Boya', 4, 5))]);
      final c = make(repo);
      await c.read(stockListProvider.future);
      c.read(stockListProvider.notifier).setQuantity('m1', 25, immediate: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.writes, [('m1', 25.0)]);
    });

    test('hata: değer sunucudakine döner ve ileti bırakılır', () async {
      final repo = FakeStockRepo(
        [StockItem.fromJson(mat('m1', 'Boya', 4, 5))],
      )..writeError = const AppException(AppErrorCode.network, 'Bağlantı yok.');
      final c = make(repo);
      await c.read(stockListProvider.future);
      c.read(stockListProvider.notifier).adjust('m1', 1);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(c.read(stockListProvider).value!.items.single.quantity, 4);
      expect(c.read(stockListProvider).value!.saving, isEmpty);
      expect(c.read(stockMessageProvider), contains('Boya güncellenemedi'));
    });

    test('silme: yerelden gizle ve geri al', () async {
      final repo = FakeStockRepo([
        StockItem.fromJson(mat('m1', 'Boya', 4, 5)),
        StockItem.fromJson(mat('m2', 'Vida', 40, 5)),
      ]);
      final c = make(repo);
      await c.read(stockListProvider.future);
      final n = c.read(stockListProvider.notifier);
      final removed = n.removeLocal('m1')!;
      expect(c.read(stockListProvider).value!.items.map((e) => e.id), ['m2']);
      n.restore(removed);
      expect(c.read(stockListProvider).value!.items.length, 2);
      n.restore(removed); // çift ekleme yok
      expect(c.read(stockListProvider).value!.items.length, 2);
    });
  });

  group('DEMO uçları', () {
    StockRepository demo(String role) {
      final db = DemoDb(now: DateTime.utc(2026, 11, 20, 8));
      final dio = Dio(BaseOptions(baseUrl: 'https://demo.test/api'))
        ..httpClientAdapter = DemoHttpAdapter(db, latency: Duration.zero)
        ..options.headers['Authorization'] = 'Bearer demo-token-$role';
      return HttpStockRepository(ApiClient(dio));
    }

    test('ekle, ± , düzenle, sil; geçersiz değer 400; rol 403', () async {
      final r = demo('admin');
      final before = (await r.list()).length;
      final created = await r.create(
        const StockInput(name: 'Test', quantity: 3, minStock: 2),
      );
      expect((await r.list()).length, before + 1);
      await r.setQuantity(created.id, 9);
      expect(
        (await r.list()).firstWhere((e) => e.id == created.id).quantity,
        9,
      );
      await r.update(
        created.id,
        const StockInput(name: 'Test 2', quantity: 9, minStock: 10),
      );
      final u = (await r.list()).firstWhere((e) => e.id == created.id);
      expect(u.name, 'Test 2');
      expect(u.isLow, isTrue);
      await expectLater(
        r.create(const StockInput(name: '')),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'c',
            AppErrorCode.validation,
          ),
        ),
      );
      await r.delete(created.id);
      expect((await r.list()).length, before);
      for (final role in ['personel', 'saha']) {
        await expectLater(
          demo(role).list(),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'c',
              AppErrorCode.forbidden,
            ),
          ),
        );
      }
    });
  });
}
