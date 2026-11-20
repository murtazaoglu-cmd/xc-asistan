// SAHİBİ: finance ajanı. Başka feature bu dosyaya yazmaz.
// Para veri erişimi. Uçlar (sözleşme §4-5, /mnt/user-data/outputs/mobile-api-contract.md):
//   - POST /projects/:id/payments, GET /projects/payments/all, PATCH/DELETE /projects/payments/:id
//   - GET/POST/PATCH/DELETE /expenses (proje bağlı: project_id)
//   - GET/POST/PATCH/DELETE /recurring-expenses (+ POST /:id/apply)  — A M O
//   - Proje seçici / alacak: GET /projects (?q ?limit ?offset), GET /projects/:id/full
// Tüm metotlar AppException fırlatır. saha: tüm uçlar 403 (arayüz de göstermez).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/api/api_providers.dart';
import '../../../core/util/json.dart';
import '../../../core/util/money.dart';
import '../../../core/util/phone.dart';
import 'finance_models.dart';

abstract class FinanceRepository {
  // ---- Ödemeler ----
  Future<List<Payment>> listPayments();
  Future<Payment> createPayment(String projectId, PaymentInput input);
  Future<Payment> updatePayment(String id, PaymentInput input);
  Future<void> deletePayment(String id);

  // ---- Giderler ----
  Future<List<Expense>> listExpenses();
  Future<Expense> createExpense(ExpenseInput input);
  Future<Expense> updateExpense(String id, ExpenseInput input);
  Future<void> deleteExpense(String id);

  // ---- Sabit giderler ----
  Future<List<RecurringExpense>> listRecurring();
  Future<RecurringExpense> createRecurring(RecurringInput input);
  Future<RecurringExpense> updateRecurring(String id, RecurringInput input);
  Future<void> deleteRecurring(String id);

  /// Bu ayın gider kaydını oluşturur (201). Aynı ay tekrar → 409 (AppException.conflict).
  Future<Expense> applyRecurring(String id);

  // ---- Projeler (seçici + alacak) ----
  /// Aramalı proje listesi (`?q`, en çok [limit]).
  Future<List<ProjectRef>> searchProjects({String? query, int limit = 30});

  /// Tüm projeler (alacak hesabı): sayfa sayfa çeker.
  Future<List<ProjectRef>> allProjects();

  /// Tek proje (+ ilave işler toplamı). Bulunamazsa AppException.notFound.
  Future<ProjectRef> project(String id);

  /// Projeye erişen kişiler (kayıt sahibi adayları): `GET /projects/:id/collaborators`.
  /// Yetkisiz (403) ya da uç yoksa (404) boş liste döner: seçici sessizce gizlenir.
  Future<List<OwnerRef>> projectPeople(String projectId);

  /// Müşteri adından telefon (WhatsApp hatırlatma için); bulunamazsa null.
  Future<String?> customerPhone(String customerName);
}

class HttpFinanceRepository implements FinanceRepository {
  HttpFinanceRepository(this.api);
  final ApiClient api;

  static const int _pageSize = 200;
  static const int _maxPages = 5;

  // ---- Ödemeler ----
  @override
  Future<List<Payment>> listPayments() async =>
      (await api.getList('/projects/payments/all'))
          .map(Payment.fromJson)
          .toList();

  @override
  Future<Payment> createPayment(String projectId, PaymentInput input) async {
    final body = input.toJson()..removeWhere((_, v) => v == null);
    final res = await api.post('/projects/$projectId/payments', data: body);
    return Payment.fromJson(asJsonMap(res));
  }

  @override
  Future<Payment> updatePayment(String id, PaymentInput input) async {
    final res = await api.patch('/projects/payments/$id', data: input.toJson());
    return Payment.fromJson(asJsonMap(res));
  }

  @override
  Future<void> deletePayment(String id) async {
    await api.delete('/projects/payments/$id');
  }

  // ---- Giderler ----
  @override
  Future<List<Expense>> listExpenses() async =>
      (await api.getList('/expenses')).map(Expense.fromJson).toList();

  @override
  Future<Expense> createExpense(ExpenseInput input) async => Expense.fromJson(
    asJsonMap(await api.post('/expenses', data: input.toCreateJson())),
  );

  @override
  Future<Expense> updateExpense(String id, ExpenseInput input) async =>
      Expense.fromJson(
        asJsonMap(await api.patch('/expenses/$id', data: input.toPatchJson())),
      );

  @override
  Future<void> deleteExpense(String id) async {
    await api.delete('/expenses/$id');
  }

  // ---- Sabit giderler ----
  @override
  Future<List<RecurringExpense>> listRecurring() async =>
      (await api.getList('/recurring-expenses'))
          .map(RecurringExpense.fromJson)
          .toList();

  @override
  Future<RecurringExpense> createRecurring(RecurringInput input) async =>
      RecurringExpense.fromJson(
        asJsonMap(
          await api.post('/recurring-expenses', data: input.toCreateJson()),
        ),
      );

  @override
  Future<RecurringExpense> updateRecurring(
    String id,
    RecurringInput input,
  ) async => RecurringExpense.fromJson(
    asJsonMap(
      await api.patch('/recurring-expenses/$id', data: input.toPatchJson()),
    ),
  );

  @override
  Future<void> deleteRecurring(String id) async {
    await api.delete('/recurring-expenses/$id');
  }

  @override
  Future<Expense> applyRecurring(String id) async => Expense.fromJson(
    asJsonMap(await api.post('/recurring-expenses/$id/apply')),
  );

  // ---- Projeler ----
  @override
  Future<List<ProjectRef>> searchProjects({
    String? query,
    int limit = 30,
  }) async {
    final q = (query ?? '').trim();
    final rows = await api.getList(
      '/projects',
      query: {
        if (q.isNotEmpty) 'q': q.length > 100 ? q.substring(0, 100) : q,
        'limit': limit.clamp(1, 200),
      },
    );
    return rows.map(ProjectRef.fromJson).toList();
  }

  @override
  Future<List<ProjectRef>> allProjects() async {
    final out = <ProjectRef>[];
    for (var page = 0; page < _maxPages; page++) {
      final res = await api.getPaged(
        '/projects',
        query: {'limit': _pageSize, 'offset': page * _pageSize},
      );
      out.addAll(res.items.map(ProjectRef.fromJson));
      if (!res.hasMore(page * _pageSize) || res.items.isEmpty) break;
    }
    return out;
  }

  @override
  Future<ProjectRef> project(String id) async {
    final full = await api.getMap('/projects/$id/full');
    final p = ProjectRef.fromJson(full.mapOrNull('project') ?? {});
    final paid = Money.sum(full.list('payments').map((e) => e.money('amount')));
    final extras = Money.sum(full.list('extras').map((e) => e.money('amount')));
    // `project` içinde paid_amount yoksa ödemelerden hesaplanır (aynı defter).
    final hasPaid = (full.mapOrNull('project') ?? {}).containsKey(
      'paid_amount',
    );
    return p.copyWith(paid: hasPaid ? p.paid : paid, extras: extras);
  }

  @override
  Future<List<OwnerRef>> projectPeople(String projectId) async {
    try {
      return (await api.getList('/projects/$projectId/collaborators'))
          .map(OwnerRef.fromJson)
          .where((e) => e.id.isNotEmpty)
          .toList();
    } on AppException catch (e) {
      if (e.code == AppErrorCode.forbidden || e.code == AppErrorCode.notFound) {
        return const [];
      }
      rethrow;
    }
  }

  @override
  Future<String?> customerPhone(String customerName) async {
    final name = customerName.trim();
    if (name.isEmpty) return null;
    final rows = await api.getList(
      '/customers',
      query: {'q': name, 'limit': 10},
    );
    String norm(String s) => s.trim().toLowerCase();
    for (final r in rows) {
      final phone = r.strOrNull('phone');
      if (phone != null &&
          norm(r.strOr('name')) == norm(name) &&
          PhoneUtil.toInternational(phone) != null) {
        return phone;
      }
    }
    return null;
  }
}

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => HttpFinanceRepository(ref.watch(apiClientProvider)),
);
