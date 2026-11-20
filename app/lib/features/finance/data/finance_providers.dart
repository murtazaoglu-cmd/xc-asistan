// Para sağlayıcıları (Riverpod) ve değişiklik denetleyicisi.
// Kayıt/silme sonrası ilgili sağlayıcılar yenilenir (özet, listeler, alacaklar, proje seçici);
// başka modüller (jobs proje ekranı) `financeChangesProvider`'ı dinleyip kendi verisini yeniler.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/auth/session.dart';
import '../../../core/util/dates.dart';
import 'finance_access.dart';
import 'finance_calc.dart';
import 'finance_input.dart';
import 'finance_models.dart';
import 'finance_period.dart';
import 'finance_repository.dart';

/// Rol görünürlüğü; oturum yoksa null.
final financeAccessProvider = Provider<FinanceAccess?>((ref) {
  final caps = ref.watch(capabilitiesProvider);
  return caps == null ? null : FinanceAccess.of(caps);
});

/// Ödeme yöntemi seçenekleri: invoices_vat çek/senet eklemek için bunu override eder.
final paymentMethodOptionsProvider = Provider<List<PaymentMethodOption>>(
  (ref) => PaymentMethodOption.standard,
);

final paymentsProvider = FutureProvider.autoDispose<List<Payment>>(
  (ref) => ref.watch(financeRepositoryProvider).listPayments(),
);

final expensesProvider = FutureProvider.autoDispose<List<Expense>>(
  (ref) => ref.watch(financeRepositoryProvider).listExpenses(),
);

final recurringProvider = FutureProvider.autoDispose<List<RecurringExpense>>(
  (ref) => ref.watch(financeRepositoryProvider).listRecurring(),
);

/// Tüm projeler (alacak hesabı için).
final allProjectsProvider = FutureProvider.autoDispose<List<ProjectRef>>(
  (ref) => ref.watch(financeRepositoryProvider).allProjects(),
);

/// Kalan bakiyesi olan projeler (vadesi geçenler önce).
final receivablesProvider = FutureProvider.autoDispose<List<Receivable>>((
  ref,
) async {
  final projects = await ref.watch(allProjectsProvider.future);
  return FinanceCalc.receivables(projects);
});

/// Proje seçici araması (boş sorgu = son projeler).
final projectSearchProvider = FutureProvider.autoDispose
    .family<List<ProjectRef>, String>(
      (ref, q) => ref.watch(financeRepositoryProvider).searchProjects(query: q),
    );

/// Tek proje (kalan bakiye için); form `projectId` ile açıldığında kullanılır.
final projectByIdProvider = FutureProvider.autoDispose
    .family<ProjectRef, String>(
      (ref, id) => ref.watch(financeRepositoryProvider).project(id),
    );

class SelectedMonthNotifier extends Notifier<YearMonth> {
  @override
  YearMonth build() => YearMonth.now();

  void previous() => state = state.previous;

  /// Gelecek aya geçilmez (kayıt yok).
  void next() {
    final n = state.next;
    if (n > YearMonth.now()) return;
    state = n;
  }

  void set(YearMonth m) => state = m > YearMonth.now() ? YearMonth.now() : m;
  bool get canGoNext => state.next <= YearMonth.now();
}

final selectedMonthProvider =
    NotifierProvider<SelectedMonthNotifier, YearMonth>(
      SelectedMonthNotifier.new,
    );

/// Serbest tarih aralığı (null: ay seçici geçerli). Özet/Ödemeler/Giderler bunu kullanır.
class CustomPeriodNotifier extends Notifier<FinancePeriod?> {
  @override
  FinancePeriod? build() => null;

  /// Başlangıç ve bitiş GÜN DAHİL. Bugünden sonrası bugüne kırpılır (kayıt gelecekte olmaz).
  void setRange(DateTime start, DateTime end) {
    final now = Ist.now();
    DateTime clamp(DateTime d) => d.isAfter(now) ? now : d;
    state = FinancePeriod.custom(clamp(start), clamp(end));
  }

  void clear() => state = null;
}

final customPeriodProvider =
    NotifierProvider<CustomPeriodNotifier, FinancePeriod?>(
      CustomPeriodNotifier.new,
    );

/// Etkin dönem: serbest aralık varsa o, yoksa seçili ay.
final activePeriodProvider = Provider<FinancePeriod>((ref) {
  final custom = ref.watch(customPeriodProvider);
  if (custom != null) return custom;
  return FinancePeriod.month(ref.watch(selectedMonthProvider));
});

/// Kullanıcı kimliği → ad (oturumdaki ben + ekip; sunucu `team` ve `user`).
final ownerDirectoryProvider = Provider<OwnerDirectory>((ref) {
  final s = ref.watch(sessionProvider);
  if (s is! SessionAuthenticated) return OwnerDirectory.empty;
  return OwnerDirectory(
    selfId: s.user.id,
    names: {for (final t in s.me.team) t.id: t.name, s.user.id: s.user.name},
  );
});

/// Kayıt sahibi adayları (defter sahibi seçici). `projectId` null → projeye bağlı olmayan gider
/// (yalnız yönetici başkasına atayabilir). Yönetici: ben + ekip + projeye erişenler;
/// diğer roller: ben + projeye erişenler. İlk eleman her zaman "ben" (varsayılan).
final ownerCandidatesProvider = FutureProvider.autoDispose
    .family<List<OwnerRef>, String?>((ref, projectId) async {
      final dir = ref.watch(ownerDirectoryProvider);
      final role = ref.watch(capabilitiesProvider)?.role;
      final selfId = dir.selfId;
      if (selfId == null || role == null) return const [];
      final out = <String, OwnerRef>{
        selfId: OwnerRef(id: selfId, name: dir.names[selfId] ?? 'Ben'),
      };
      if (role == UserRole.admin) {
        dir.names.forEach(
          (id, n) => out.putIfAbsent(id, () => OwnerRef(id: id, name: n)),
        );
      }
      if (projectId != null && projectId.isNotEmpty) {
        final people = await ref
            .watch(financeRepositoryProvider)
            .projectPeople(projectId);
        for (final p in people) {
          out.putIfAbsent(p.id, () => p);
        }
      } else if (role != UserRole.admin) {
        return const [];
      }
      return out.values.toList();
    });

/// Her kayıt/silme/uygulamada artar: diğer modüller (proje ekranı) bunu dinleyip yenilenir.
class FinanceChangesNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final financeChangesProvider = NotifierProvider<FinanceChangesNotifier, int>(
  FinanceChangesNotifier.new,
);

/// "Geri al" penceresindeki (silinmesi ertelenen) kayıt kimlikleri: listeler bunları gizler.
class PendingDeletesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};
  void add(String id) => state = {...state, id};
  void remove(String id) => state = {...state}..remove(id);
}

final pendingDeletesProvider =
    NotifierProvider<PendingDeletesNotifier, Set<String>>(
      PendingDeletesNotifier.new,
    );

/// Yazma işlemleri: repository çağırır, sonra sağlayıcıları yeniler. Nesne `Ref` taşır
/// ama ekrandan bağımsızdır (geri al kapanışlarında ekran kapalı olsa da güvenle çağrılır).
class FinanceController {
  FinanceController(this._ref);
  final Ref _ref;

  FinanceRepository get _repo => _ref.read(financeRepositoryProvider);

  void _changed() {
    _ref.invalidate(paymentsProvider);
    _ref.invalidate(expensesProvider);
    _ref.invalidate(allProjectsProvider);
    _ref.invalidate(projectSearchProvider);
    _ref.invalidate(projectByIdProvider);
    _ref.read(financeChangesProvider.notifier).bump();
  }

  // ---- Ödeme ----
  Future<Payment> addPayment(ProjectRef project, PaymentInput input) async {
    final p = await _repo.createPayment(project.id, input);
    _changed();
    return p.copyWith(
      customerName: project.customerName,
      projectCode: project.code,
    );
  }

  Future<Payment> editPayment(Payment old, PaymentInput input) async {
    final p = await _repo.updatePayment(old.id, input);
    _changed();
    return p.copyWith(
      customerName: old.customerName,
      projectCode: old.projectCode,
    );
  }

  /// Gerçek DELETE (ertelenmiş silme tamamlanırken ya da "geri al" ile oluşturulan kaydı kaldırırken).
  Future<void> removePayment(String id) async {
    await _repo.deletePayment(id);
    _changed();
  }

  // ---- Gider ----
  Future<Expense> addExpense(ExpenseInput input, {ProjectRef? project}) async {
    final e = await _repo.createExpense(input);
    _changed();
    return project == null
        ? e
        : e.copyWith(
            customerName: project.customerName,
            projectCode: project.code,
          );
  }

  Future<Expense> editExpense(Expense old, ExpenseInput input) async {
    final e = await _repo.updateExpense(old.id, input);
    _changed();
    return e.copyWith(
      customerName: old.customerName,
      projectCode: old.projectCode,
    );
  }

  Future<void> removeExpense(String id) async {
    await _repo.deleteExpense(id);
    _changed();
  }

  // ---- Sabit gider ----
  Future<RecurringExpense> addRecurring(RecurringInput input) async {
    final r = await _repo.createRecurring(input);
    _ref.invalidate(recurringProvider);
    return r;
  }

  Future<RecurringExpense> editRecurring(
    String id,
    RecurringInput input,
  ) async {
    final r = await _repo.updateRecurring(id, input);
    _ref.invalidate(recurringProvider);
    return r;
  }

  Future<void> removeRecurring(String id) async {
    await _repo.deleteRecurring(id);
    _ref.invalidate(recurringProvider);
  }

  /// 409 (bu ay zaten eklenmiş) AppException olarak yukarı çıkar; arayüz nazikçe gösterir.
  Future<Expense> applyRecurring(String id) async {
    final e = await _repo.applyRecurring(id);
    _changed();
    return e;
  }
}

final financeControllerProvider = Provider<FinanceController>(
  FinanceController.new,
);
