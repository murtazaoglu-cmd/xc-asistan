// Sağlayıcılar (Riverpod) ve yazma denetleyicisi. Yazma sonrası ilgili listeler yenilenir.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart' show Paged;
import '../../../core/auth/session.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/formatters.dart';
import 'invoices_vat_access.dart';
import 'invoices_vat_models.dart';
import 'invoices_vat_repository.dart';

/// Rol görünürlüğü; oturum yoksa null.
final invoicesVatAccessProvider = Provider<InvoicesVatAccess?>((ref) {
  final caps = ref.watch(capabilitiesProvider);
  return caps == null ? null : InvoicesVatAccess.of(caps);
});

// ---------------------------------------------------------------- Dönem seçimi

/// Takvim ayı (İstanbul). Aylık: "2026-11"; 3 aylık: "2026-Q4".
@immutable
class PeriodSel {
  const PeriodSel(this.year, this.month);
  final int year;

  /// 1-12 (aylık) — 3 aylıkta çeyreğin son ayı değil, çeyrek numarası için [quarter] kullanılır.
  final int month;

  factory PeriodSel.now([DateTime? now]) {
    final w = Ist.wall(now ?? Ist.now());
    return PeriodSel(w.year, w.month);
  }

  int get quarter => ((month - 1) ~/ 3) + 1;

  String get monthKey => '$year-${month.toString().padLeft(2, '0')}';
  String get quarterKey => '$year-Q$quarter';

  PeriodSel get previousMonth =>
      month == 1 ? PeriodSel(year - 1, 12) : PeriodSel(year, month - 1);
  PeriodSel get nextMonth =>
      month == 12 ? PeriodSel(year + 1, 1) : PeriodSel(year, month + 1);

  String get monthLabel => '${Fmt.monthsLong[month - 1]} $year';

  @override
  bool operator ==(Object other) =>
      other is PeriodSel && other.year == year && other.month == month;
  @override
  int get hashCode => Object.hash(year, month);
}

/// KDV sekmesi dönem seçimi: ay + aylık/3 aylık tür.
@immutable
class VatSelection {
  const VatSelection(this.period, {this.quarterly = false});
  final PeriodSel period;
  final bool quarterly;

  String get key => quarterly ? period.quarterKey : period.monthKey;
  String get label => quarterly
      ? '${period.quarter}. çeyrek ${period.year}'
      : period.monthLabel;

  VatSelection step(int dir) {
    if (!quarterly) {
      return VatSelection(dir > 0 ? period.nextMonth : period.previousMonth);
    }
    var m = period.month + 3 * dir;
    var y = period.year;
    while (m > 12) {
      m -= 12;
      y++;
    }
    while (m < 1) {
      m += 12;
      y--;
    }
    return VatSelection(PeriodSel(y, m), quarterly: true);
  }

  VatSelection withQuarterly(bool q) => VatSelection(period, quarterly: q);

  @override
  bool operator ==(Object other) =>
      other is VatSelection &&
      other.period == period &&
      other.quarterly == quarterly;
  @override
  int get hashCode => Object.hash(period, quarterly);
}

class VatSelectionNotifier extends Notifier<VatSelection> {
  @override
  VatSelection build() => VatSelection(PeriodSel.now());
  void step(int dir) => state = state.step(dir);
  void setQuarterly(bool q) => state = state.withQuarterly(q);
  void set(VatSelection s) => state = s;
}

final vatSelectionProvider =
    NotifierProvider<VatSelectionNotifier, VatSelection>(
      VatSelectionNotifier.new,
    );

// ---------------------------------------------------------------- Fatura filtresi

@immutable
class InvoiceFilter {
  const InvoiceFilter({
    this.direction,
    this.statuses = const {},
    this.period,
    this.query = '',
    this.overdueOnly = false,
    this.limit = 100,
  });
  final InvoiceDirection? direction;
  final Set<InvoiceStatus> statuses;

  /// null = tüm dönemler.
  final PeriodSel? period;
  final String query;
  final bool overdueOnly;
  final int limit;

  InvoiceFilter copyWith({
    Object? direction = _keep,
    Set<InvoiceStatus>? statuses,
    Object? period = _keep,
    String? query,
    bool? overdueOnly,
    int? limit,
  }) => InvoiceFilter(
    direction: identical(direction, _keep)
        ? this.direction
        : direction as InvoiceDirection?,
    statuses: statuses ?? this.statuses,
    period: identical(period, _keep) ? this.period : period as PeriodSel?,
    query: query ?? this.query,
    overdueOnly: overdueOnly ?? this.overdueOnly,
    limit: limit ?? this.limit,
  );

  static const Object _keep = Object();

  InvoiceQuery toQuery() => InvoiceQuery(
    direction: direction,
    statuses: statuses,
    period: period?.monthKey,
    overdueOnly: overdueOnly,
    q: query,
    limit: limit,
  );

  bool get isActive =>
      direction != null ||
      statuses.isNotEmpty ||
      query.trim().isNotEmpty ||
      overdueOnly;
}

class InvoiceFilterNotifier extends Notifier<InvoiceFilter> {
  @override
  InvoiceFilter build() => InvoiceFilter(period: PeriodSel.now());

  void setDirection(InvoiceDirection? d) =>
      state = state.copyWith(direction: d, limit: 100);

  void toggleStatus(InvoiceStatus s) {
    final next = {...state.statuses};
    next.contains(s) ? next.remove(s) : next.add(s);
    state = state.copyWith(statuses: next, limit: 100);
  }

  void setPeriod(PeriodSel? p) => state = state.copyWith(period: p, limit: 100);
  void setQuery(String q) => state = state.copyWith(query: q, limit: 100);
  void setOverdue(bool v) => state = state.copyWith(overdueOnly: v, limit: 100);
  void loadMore() => state = state.copyWith(limit: state.limit + 100);
  void clear() => state = InvoiceFilter(period: state.period);
}

final invoiceFilterProvider =
    NotifierProvider<InvoiceFilterNotifier, InvoiceFilter>(
      InvoiceFilterNotifier.new,
    );

// ---------------------------------------------------------------- Veri sağlayıcıları

final invoiceListProvider = FutureProvider.autoDispose<Paged<Invoice>>((ref) {
  final f = ref.watch(invoiceFilterProvider);
  return ref.watch(invoicesVatRepositoryProvider).listInvoices(f.toQuery());
});

final invoiceDetailProvider = FutureProvider.autoDispose
    .family<Invoice, String>(
      (ref, id) => ref.watch(invoicesVatRepositoryProvider).invoice(id),
    );

final invoiceSummaryProvider = FutureProvider.autoDispose
    .family<InvoiceSummary, String>(
      (ref, period) =>
          ref.watch(invoicesVatRepositoryProvider).invoiceSummary(period),
    );

/// Oran listesi (teyit rozetleriyle). Sık değişmez: oturum boyunca saklanır.
final vatRatesProvider = FutureProvider<VatRates>(
  (ref) => ref.watch(invoicesVatRepositoryProvider).vatRates(),
);

final vatPeriodProvider = FutureProvider.autoDispose.family<VatPeriod, String>(
  (ref, ym) => ref.watch(invoicesVatRepositoryProvider).vatPeriod(ym),
);

/// Vergi takvimi (yaklaşan 120 gün).
final taxCalendarProvider = FutureProvider.autoDispose<TaxCalendar>(
  (ref) => ref.watch(invoicesVatRepositoryProvider).taxCalendar(days: 120),
);

@immutable
class ScheduleFilter {
  const ScheduleFilter({this.projectId, this.offerId, this.status});
  final String? projectId;
  final String? offerId;
  final String? status;
  @override
  bool operator ==(Object other) =>
      other is ScheduleFilter &&
      other.projectId == projectId &&
      other.offerId == offerId &&
      other.status == status;
  @override
  int get hashCode => Object.hash(projectId, offerId, status);
}

final scheduleProvider = FutureProvider.autoDispose
    .family<List<ScheduleItem>, ScheduleFilter>(
      (ref, f) => ref
          .watch(invoicesVatRepositoryProvider)
          .schedule(
            projectId: f.projectId,
            offerId: f.offerId,
            status: f.status,
          ),
    );

final agingProvider = FutureProvider.autoDispose.family<AgingReport, String?>(
  (ref, projectId) =>
      ref.watch(invoicesVatRepositoryProvider).aging(projectId: projectId),
);

final reminderTemplatesProvider =
    FutureProvider.autoDispose<List<MessageTemplate>>(
      (ref) =>
          ref.watch(invoicesVatRepositoryProvider).templates(category: 'odeme'),
    );

enum RefKind { project, customer }

final refSearchProvider = FutureProvider.autoDispose
    .family<List<RefItem>, ({RefKind kind, String q})>((ref, a) {
      final repo = ref.watch(invoicesVatRepositoryProvider);
      return a.kind == RefKind.project
          ? repo.searchProjects(a.q)
          : repo.searchCustomers(a.q);
    });

/// Yazma sonrası tüm ilgili sağlayıcıları yeniler (fatura ↔ KDV ↔ plan ↔ yaşlandırma bağlıdır).
void invalidateInvoicesVat(Ref ref) {
  ref.invalidate(invoiceListProvider);
  ref.invalidate(invoiceDetailProvider);
  ref.invalidate(invoiceSummaryProvider);
  ref.invalidate(vatPeriodProvider);
  ref.invalidate(taxCalendarProvider);
  ref.invalidate(scheduleProvider);
  ref.invalidate(agingProvider);
}

/// Widget tarafından (WidgetRef) aynı yenileme.
void invalidateInvoicesVatW(WidgetRef ref) {
  ref.invalidate(invoiceListProvider);
  ref.invalidate(invoiceDetailProvider);
  ref.invalidate(invoiceSummaryProvider);
  ref.invalidate(vatPeriodProvider);
  ref.invalidate(taxCalendarProvider);
  ref.invalidate(scheduleProvider);
  ref.invalidate(agingProvider);
}
