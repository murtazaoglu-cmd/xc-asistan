// SAHİBİ: stock ajanı. Başka feature bu dosyaya yazmaz.
// Uçlar (sözleşme §11; A M O): GET/POST /materials · PATCH/DELETE /materials/:id
// (stok ± için {stock_quantity}). Liste sayfalamasızdır (tam liste).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/api/api_providers.dart';
import 'stock_models.dart';

/// Hata durumunda ekran hemen "Tekrar dene" göstermeli (GET'leri ApiClient zaten dener).
Duration? _noRetry(int retryCount, Object error) => null;

abstract class StockRepository {
  Future<List<StockItem>> list();
  Future<StockItem> create(StockInput input);
  Future<StockItem> update(String id, StockInput input);

  /// Hızlı +/-: yalnız `{stock_quantity}` gönderilir.
  Future<void> setQuantity(String id, double quantity);
  Future<void> delete(String id);
}

class HttpStockRepository implements StockRepository {
  HttpStockRepository(this.api);
  final ApiClient api;

  @override
  Future<List<StockItem>> list() async =>
      (await api.getList('/materials')).map(StockItem.fromJson).toList();

  @override
  Future<StockItem> create(StockInput input) async => StockItem.fromJson(
    asMap(await api.post('/materials', data: input.toJson())),
  );

  @override
  Future<StockItem> update(String id, StockInput input) async =>
      StockItem.fromJson(
        asMap(
          await api.patch(
            '/materials/${Uri.encodeComponent(id)}',
            data: input.toJson(),
          ),
        ),
      );

  @override
  Future<void> setQuantity(String id, double quantity) async {
    await api.patch(
      '/materials/${Uri.encodeComponent(id)}',
      data: {'stock_quantity': StockQty.toJson(quantity)},
    );
  }

  @override
  Future<void> delete(String id) async {
    await api.delete('/materials/${Uri.encodeComponent(id)}');
  }

  static Map<String, dynamic> asMap(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
}

final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => HttpStockRepository(ref.watch(apiClientProvider)),
);

// ---- Liste durumu: iyimser +/- (birleştirilmiş yazma), silme+geri al ----

class StockState {
  const StockState({required this.items, this.saving = const {}});
  final List<StockItem> items;

  /// Sunucuya yazılması süren/bekleyen malzemeler.
  final Set<String> saving;

  int get lowCount => items.where((e) => e.isLow).length;

  StockState copy({List<StockItem>? items, Set<String>? saving}) =>
      StockState(items: items ?? this.items, saving: saving ?? this.saving);
}

/// Son hata iletisi (ekran SnackBar gösterip temizler).
class StockMessageNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? m) => state = m;
}

final stockMessageProvider = NotifierProvider<StockMessageNotifier, String?>(
  StockMessageNotifier.new,
);

class StockListNotifier extends AsyncNotifier<StockState> {
  /// Art arda dokunuşlar tek PATCH'e birleşir.
  /// (Testte kısaltılabilsin diye `static` ve const değildir.)
  static Duration debounce = const Duration(milliseconds: 500);

  final Map<String, Timer> _timers = {};
  final Map<String, double> _desired = {}; // gönderilmeyi bekleyen son değer
  final Map<String, double> _confirmed = {}; // sunucunun bildiği son değer
  final Map<String, int> _inFlight = {};
  late StockRepository _repo;

  @override
  Future<StockState> build() async {
    _repo = ref.read(stockRepositoryProvider);
    ref.onDispose(() {
      // Ekrandan çıkarken bekleyen yazmaları kaybetme.
      for (final t in _timers.values) {
        t.cancel();
      }
      _desired.forEach((id, q) {
        _repo.setQuantity(id, q).catchError((_) {});
      });
      _timers.clear();
      _desired.clear();
    });
    final items = await _repo.list();
    return StockState(items: items);
  }

  StockItem? _find(String id) {
    for (final i in state.value?.items ?? const <StockItem>[]) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// +/- : [delta] kadar değiştirir (0'ın altına inmez).
  void adjust(String id, double delta) {
    final it = _find(id);
    if (it == null) return;
    setQuantity(id, it.quantity + delta);
  }

  /// Mutlak değer yaz (ör. değer girişi). [immediate] bekleme olmadan gönderir.
  void setQuantity(String id, double value, {bool immediate = false}) {
    final it = _find(id);
    final cur = state.value;
    if (it == null || cur == null) return;
    final q = StockQty.round(value < 0 ? 0 : value);
    _confirmed.putIfAbsent(id, () => it.quantity);
    _desired[id] = q;
    state = AsyncData(
      cur.copy(
        items: [
          for (final e in cur.items) e.id == id ? e.copyWith(quantity: q) : e,
        ],
        saving: {...cur.saving, id},
      ),
    );
    _timers[id]?.cancel();
    if (immediate) {
      _commit(id);
    } else {
      _timers[id] = Timer(debounce, () => _commit(id));
    }
  }

  Future<void> _commit(String id) async {
    final q = _desired[id];
    if (q == null) return;
    _timers.remove(id)?.cancel();
    _desired.remove(id);
    _inFlight[id] = (_inFlight[id] ?? 0) + 1;
    try {
      await _repo.setQuantity(id, q);
      _confirmed[id] = q;
    } catch (e) {
      if (ref.mounted) {
        // Daha yeni bir değer beklemiyorsa sunucudaki son değere dön.
        if (!_desired.containsKey(id)) _revert(id);
        ref
            .read(stockMessageProvider.notifier)
            .set(
              '${_find(id)?.name ?? 'Malzeme'} güncellenemedi: ${AppException.from(e).message}',
            );
      }
    } finally {
      _inFlight[id] = (_inFlight[id] ?? 1) - 1;
      if (ref.mounted &&
          !_desired.containsKey(id) &&
          (_inFlight[id] ?? 0) <= 0) {
        final cur = state.value;
        if (cur != null) {
          state = AsyncData(cur.copy(saving: {...cur.saving}..remove(id)));
        }
      }
    }
  }

  void _revert(String id) {
    final cur = state.value;
    final back = _confirmed[id];
    if (cur == null || back == null) return;
    state = AsyncData(
      cur.copy(
        items: [
          for (final e in cur.items)
            e.id == id ? e.copyWith(quantity: back) : e,
        ],
      ),
    );
  }

  /// Silinecek malzemeyi listeden gizler; geri almak için [restore].
  StockItem? removeLocal(String id) {
    final cur = state.value;
    final it = _find(id);
    if (cur == null || it == null) return null;
    state = AsyncData(
      cur.copy(items: cur.items.where((e) => e.id != id).toList()),
    );
    return it;
  }

  void restore(StockItem item) {
    final cur = state.value;
    if (cur == null || cur.items.any((e) => e.id == item.id)) return;
    state = AsyncData(cur.copy(items: [...cur.items, item]));
  }
}

final stockListProvider =
    AsyncNotifierProvider.autoDispose<StockListNotifier, StockState>(
      StockListNotifier.new,
      retry: _noRetry,
    );

/// Arama metni ve "yalnız düşük stok" süzgeci (ekran durumu).
class StockQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

final stockQueryProvider =
    NotifierProvider.autoDispose<StockQueryNotifier, String>(
      StockQueryNotifier.new,
    );

class StockOnlyLowNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final stockOnlyLowProvider =
    NotifierProvider.autoDispose<StockOnlyLowNotifier, bool>(
      StockOnlyLowNotifier.new,
    );

/// Arama + süzgeç + sıralama (düşük stok önce, sonra Türkçe ada göre). Saf mantık.
List<StockItem> filterStock(
  List<StockItem> items, {
  String query = '',
  bool onlyLow = false,
}) {
  final q = query.trim().toLowerCase();
  final out = items.where((e) {
    if (onlyLow && !e.isLow) return false;
    if (q.isEmpty) return true;
    return e.name.toLowerCase().contains(q) ||
        (e.note ?? '').toLowerCase().contains(q) ||
        e.unit.toLowerCase().contains(q);
  }).toList();
  out.sort((a, b) {
    if (a.isLow != b.isLow) return a.isLow ? -1 : 1;
    return _trCompare(a.name, b.name);
  });
  return out;
}

const String _alpha = 'abcçdefgğhıijklmnoöprsştuüvyz';
int _trCompare(String a, String b) {
  String low(String s) =>
      s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  int r(String c) {
    final i = _alpha.indexOf(c);
    return i >= 0 ? i + 100 : c.codeUnitAt(0);
  }

  final x = low(a), y = low(b);
  final n = x.length < y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final d = r(x[i]) - r(y[i]);
    if (d != 0) return d;
  }
  return x.length - y.length;
}
