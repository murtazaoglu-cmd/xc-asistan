// SAHİBİ: customers ajanı. Başka feature bu dosyaya yazmaz.
// Uçlar (sözleşme §6-§7; A M O):
//   - GET/POST /customers (?q ?limit ?offset; toplam X-Total-Count)
//   - GET/PATCH/DELETE /customers/:phoneKey
// Silme uçları geri alınamaz: arayüz `UndoSnackbar.deferred` ile geciktirir.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/api/api_providers.dart';
import '../../../core/util/phone.dart';
import 'customer_models.dart';
import 'customer_search.dart';

/// Riverpod 3 varsayılan yeniden denemesi kapalı: GET'leri ApiClient zaten yeniden dener,
/// hata durumunda ekran hemen "Tekrar dene" göstermeli.
Duration? _noRetry(int retryCount, Object error) => null;

abstract class CustomersRepository {
  /// Müşteri sayfası. [query] ham arama metnidir; normalleştirme burada yapılır.
  Future<Paged<Customer>> list({
    String query = '',
    int limit = 50,
    int offset = 0,
  });

  /// Tek müşteri (telefon anahtarıyla). Bulunamazsa `AppErrorCode.notFound`.
  Future<Customer> get(String phoneKey);

  /// Yinelenen telefon denetimi: aynı `phone_key`li müşteri ya da null.
  Future<Customer?> findByPhone(String phone);

  Future<CustomerHistory> history(String phoneKey);
  Future<Customer> create(CustomerInput input);
  Future<void> update(String phoneKey, CustomerInput input);
  Future<void> delete(String phoneKey);
}

class HttpCustomersRepository implements CustomersRepository {
  HttpCustomersRepository(this.api);
  final ApiClient api;

  @override
  Future<Paged<Customer>> list({
    String query = '',
    int limit = 50,
    int offset = 0,
  }) async {
    final q = CustomerSearch.normalizeQuery(query);
    final page = await api.getPaged(
      '/customers',
      query: {'q': q, 'limit': limit, 'offset': offset},
    );
    return Paged(page.items.map(Customer.fromJson).toList(), page.total);
  }

  @override
  Future<Customer?> findByPhone(String phone) async {
    final key = PhoneUtil.phoneKey(phone);
    if (key.length < 3) return null;
    final page = await list(query: key, limit: 20);
    for (final c in page.items) {
      if (c.phoneKey == key) return c;
    }
    return null;
  }

  @override
  Future<Customer> get(String phoneKey) async {
    final found = await findByPhone(phoneKey);
    if (found == null) {
      throw const AppException(AppErrorCode.notFound, 'Müşteri bulunamadı.');
    }
    return found;
  }

  @override
  Future<CustomerHistory> history(String phoneKey) async =>
      CustomerHistory.fromJson(
        await api.getMap('/customers/${Uri.encodeComponent(phoneKey)}'),
      );

  @override
  Future<Customer> create(CustomerInput input) async {
    final row = await api.post('/customers', data: input.toCreateJson());
    final map = row is Map
        ? Customer.fromJson(Map<String, dynamic>.from(row))
        : null;
    if (map != null && map.phoneKey.isNotEmpty) {
      return map.name.isEmpty
          ? Customer(
              phoneKey: map.phoneKey,
              name: input.name.trim(),
              phone: input.phone,
            )
          : map;
    }
    return Customer(
      phoneKey: input.phoneKey,
      name: input.name.trim(),
      phone: input.phone.trim(),
    );
  }

  @override
  Future<void> update(String phoneKey, CustomerInput input) async {
    try {
      await api.patch(
        '/customers/${Uri.encodeComponent(phoneKey)}',
        data: input.toPatchJson(),
      );
    } on AppException catch (e) {
      // Sözleşme: tekliften türeyen müşteri için 404 (teklifin kendisi düzenlenir).
      if (e.code == AppErrorCode.notFound) {
        throw AppException(
          AppErrorCode.notFound,
          'Bu müşteri tekliften geldiği için buradan düzenlenemez. Bilgileri ilgili teklif üzerinden değiştirin.',
          statusCode: e.statusCode,
          body: e.body,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> delete(String phoneKey) async {
    await api.delete('/customers/${Uri.encodeComponent(phoneKey)}');
  }
}

final customersRepositoryProvider = Provider<CustomersRepository>(
  (ref) => HttpCustomersRepository(ref.watch(apiClientProvider)),
);

/// Müşteri kartı verileri (derin bağlantı için tek müşteri de buradan gelir).
final customerProvider = FutureProvider.autoDispose.family<Customer, String>(
  (ref, key) => ref.watch(customersRepositoryProvider).get(key),
  retry: _noRetry,
);

final customerHistoryProvider = FutureProvider.autoDispose
    .family<CustomerHistory, String>(
      (ref, key) => ref.watch(customersRepositoryProvider).history(key),
      retry: _noRetry,
    );

// ---- Liste durumu (arama + sayfalama) ----

class CustomerQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String q) => state = q;
}

final customerQueryProvider =
    NotifierProvider.autoDispose<CustomerQueryNotifier, String>(
      CustomerQueryNotifier.new,
    );

/// Silinmesi bekleyen (geri al süresindeki) müşteriler listeden gizlenir.
class PendingDeletesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};
  void add(String key) => state = {...state, key};
  void remove(String key) => state = {...state}..remove(key);
}

final pendingCustomerDeletesProvider =
    NotifierProvider<PendingDeletesNotifier, Set<String>>(
      PendingDeletesNotifier.new,
    );

class CustomerListState {
  const CustomerListState({
    required this.items,
    required this.total,
    this.loadingMore = false,
    this.loadMoreError,
  });
  final List<Customer> items;
  final int total;
  final bool loadingMore;
  final AppException? loadMoreError;

  bool get hasMore => items.length < total;

  CustomerListState copyWith({
    List<Customer>? items,
    int? total,
    bool? loadingMore,
    AppException? loadMoreError,
    bool clearError = false,
  }) => CustomerListState(
    items: items ?? this.items,
    total: total ?? this.total,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
  );
}

class CustomerListNotifier extends AsyncNotifier<CustomerListState> {
  static const int pageSize = 50;

  @override
  Future<CustomerListState> build() async {
    final q = ref.watch(customerQueryProvider);
    final page = await ref
        .read(customersRepositoryProvider)
        .list(query: q, limit: pageSize, offset: 0);
    return CustomerListState(items: page.items, total: page.total);
  }

  /// Sonraki sayfa (kaydırma sonunda ya da "Daha fazla" düğmesiyle).
  Future<void> loadMore() async {
    final cur = state.value;
    if (cur == null || cur.loadingMore || !cur.hasMore) return;
    state = AsyncData(cur.copyWith(loadingMore: true, clearError: true));
    try {
      final page = await ref
          .read(customersRepositoryProvider)
          .list(
            query: ref.read(customerQueryProvider),
            limit: pageSize,
            offset: cur.items.length,
          );
      // Aynı anahtar iki sayfada gelirse (kayıt eklendi/değişti) tekilleştir.
      final seen = {for (final c in cur.items) c.phoneKey};
      final merged = [
        ...cur.items,
        ...page.items.where((c) => seen.add(c.phoneKey)),
      ];
      state = AsyncData(CustomerListState(items: merged, total: page.total));
    } catch (e) {
      state = AsyncData(
        cur.copyWith(loadingMore: false, loadMoreError: AppException.from(e)),
      );
    }
  }
}

final customerListProvider =
    AsyncNotifierProvider.autoDispose<CustomerListNotifier, CustomerListState>(
      CustomerListNotifier.new,
      retry: _noRetry,
    );
