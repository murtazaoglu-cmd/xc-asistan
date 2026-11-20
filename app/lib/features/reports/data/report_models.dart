// Rapor modelleri (sözleşme §13). Para: kabloda TL ondalık → `Money` (kuruş).
// KÂR TANIMI: netProfit = totalRevenue − businessExpenses (yalnız scope dukkan+genel).
// `ev` (kişisel) giderler işletme kârına DAHİL DEĞİL: `homeExpenses` ayrı alan,
// `netProfitInclHome` yalnız bilgi amaçlı "hepsi dahil" görünümdür.
import 'package:flutter/foundation.dart';

import '../../../core/util/json.dart';
import '../../../core/util/money.dart';

enum ReportRange {
  monthly('monthly', 'Aylık'),
  yearly('yearly', 'Yıllık');

  const ReportRange(this.api, this.label);
  final String api;
  final String label;
}

@immutable
class ReportSummary {
  const ReportSummary({
    this.totalOffers = 0,
    this.statusCounts = const {},
    this.conversionRate = 0,
    this.totalRevenue = Money.zero,
    this.activeProjects = 0,
    this.businessExpenses = Money.zero,
    this.homeExpenses = Money.zero,
    this.expensesDukkan = Money.zero,
    this.expensesGenel = Money.zero,
    this.expensesEv = Money.zero,
    this.netProfit = Money.zero,
    this.netProfitInclHome = Money.zero,
  });

  final int totalOffers;
  final Map<String, int> statusCounts;

  /// Yüzde (örn. 16.7).
  final double conversionRate;
  final Money totalRevenue;
  final int activeProjects;
  final Money businessExpenses;
  final Money homeExpenses;
  final Money expensesDukkan;
  final Money expensesGenel;
  final Money expensesEv;

  /// İşletme net kârı (ev giderleri HARİÇ).
  final Money netProfit;

  /// Ev giderleri de düşülmüş (bilgi amaçlı).
  final Money netProfitInclHome;

  factory ReportSummary.fromJson(JsonMap j) {
    final scope = j.mapOrNull('expensesByScope') ?? const <String, dynamic>{};
    final revenue = j.money('totalRevenue');
    final business = j.money('businessExpenses');
    final home = j.money('homeExpenses');
    return ReportSummary(
      totalOffers: j.intOr('totalOffers'),
      statusCounts: {
        for (final e in asJsonMap(j['statusCounts']).entries)
          e.key: (e.value is num
              ? (e.value as num).toInt()
              : int.tryParse('${e.value}') ?? 0),
      },
      conversionRate: j.doubleOrNull('conversionRate') ?? 0,
      totalRevenue: revenue,
      activeProjects: j.intOr('activeProjects'),
      businessExpenses: business,
      homeExpenses: home,
      expensesDukkan: scope.money('dukkan'),
      expensesGenel: scope.money('genel'),
      expensesEv: scope.money('ev'),
      netProfit: j.moneyOrNull('netProfit') ?? revenue - business,
      netProfitInclHome:
          j.moneyOrNull('netProfitInclHome') ?? revenue - business - home,
    );
  }
}

/// "2026-11" (aylık) ya da "2026" (yıllık) dönem anahtarı.
@immutable
class ReportPeriod {
  const ReportPeriod(this.year, [this.month]);
  final int year;
  final int? month;

  static ReportPeriod? tryParse(String? s) {
    final m = RegExp(r'^\s*(\d{4})(?:-(\d{1,2}))?').firstMatch(s ?? '');
    if (m == null) return null;
    final month = m.group(2) == null ? null : int.parse(m.group(2)!);
    if (month != null && (month < 1 || month > 12)) return null;
    return ReportPeriod(int.parse(m.group(1)!), month);
  }

  /// Aylıkta ay sırası (yıl*12+ay-1); yıllıkta yıl.
  int get ordinal => month == null ? year : year * 12 + month! - 1;
}

@immutable
class ProfitPoint {
  const ProfitPoint({
    required this.period,
    this.revenue = Money.zero,
    this.businessExpenses = Money.zero,
    this.homeExpenses = Money.zero,
    this.netProfit = Money.zero,
    this.netProfitInclHome = Money.zero,
  });

  final String period;
  final Money revenue;
  final Money businessExpenses;
  final Money homeExpenses;
  final Money netProfit;
  final Money netProfitInclHome;

  ReportPeriod? get parsed => ReportPeriod.tryParse(period);

  /// Hiç hareket yoksa ay "boş"tur.
  bool get isEmpty =>
      revenue.isZero && businessExpenses.isZero && homeExpenses.isZero;

  factory ProfitPoint.fromJson(JsonMap j) {
    final revenue = j.money('revenue');
    final business = j.money('businessExpenses');
    final home = j.money('homeExpenses');
    return ProfitPoint(
      period: j.strOr('period'),
      revenue: revenue,
      businessExpenses: business,
      homeExpenses: home,
      netProfit: j.moneyOrNull('netProfit') ?? revenue - business,
      netProfitInclHome:
          j.moneyOrNull('netProfitInclHome') ?? revenue - business - home,
    );
  }
}

@immutable
class RevenuePoint {
  const RevenuePoint({required this.period, this.total = Money.zero});
  final String period;
  final Money total;

  factory RevenuePoint.fromJson(JsonMap j) =>
      RevenuePoint(period: j.strOr('period'), total: j.money('total'));
}

@immutable
class ServiceShare {
  const ServiceShare({required this.service, required this.count});
  final String service;
  final int count;

  factory ServiceShare.fromJson(JsonMap j) => ServiceShare(
    service: j.strOrNull('service') ?? 'Diğer',
    count: j.intOr('count'),
  );

  /// En çok olandan aza; yüzdeler toplam üzerinden (sıfır toplamda 0).
  static List<({ServiceShare item, double percent})> withPercent(
    List<ServiceShare> items,
  ) {
    final total = items.fold<int>(0, (s, e) => s + e.count);
    final sorted = [...items]..sort((a, b) => b.count.compareTo(a.count));
    return [
      for (final e in sorted)
        (item: e, percent: total == 0 ? 0.0 : e.count * 100 / total),
    ];
  }
}

/// Proje kârlılığı = tahsilat − proje giderleri (ev giderleri hariç).
/// Kaynak: `GET /projects` (total_amount, paid_amount) + `GET /expenses` (project_id).
@immutable
class ProjectProfit {
  const ProjectProfit({
    required this.id,
    required this.code,
    required this.customerName,
    this.service,
    this.contract = Money.zero,
    this.collected = Money.zero,
    this.expenses = Money.zero,
  });

  final String id;
  final String code;
  final String customerName;
  final String? service;
  final Money contract;
  final Money collected;
  final Money expenses;

  Money get profit => collected - expenses;

  /// Tahsil edilecek kalan (sözleşme − tahsilat), negatif olmaz.
  Money get outstanding => (contract - collected).clampNonNegative();

  /// Kâr marjı yüzdesi (tahsilat üzerinden); tahsilat yoksa null.
  double? get marginPercent =>
      collected.kurus <= 0 ? null : profit.kurus * 100 / collected.kurus;

  /// Projeleri ve giderleri birleştirir. `scope == 'ev'` giderler projeye yazılmaz.
  static List<ProjectProfit> compute(
    List<JsonMap> projects,
    List<JsonMap> expenses,
  ) {
    final byProject = <String, Money>{};
    for (final e in expenses) {
      final pid = e.strOrNull('project_id');
      if (pid == null || e.str('scope') == 'ev') continue;
      byProject[pid] = (byProject[pid] ?? Money.zero) + e.money('amount');
    }
    final list = [
      for (final p in projects)
        ProjectProfit(
          id: p.strOr('id'),
          code: p.strOr('code'),
          customerName: p.strOrNull('customer_name') ?? '-',
          service: p.strOrNull('service'),
          contract: p.money('total_amount'),
          collected: p.money('paid_amount'),
          expenses: byProject[p.strOr('id')] ?? Money.zero,
        ),
    ];
    return list;
  }
}
