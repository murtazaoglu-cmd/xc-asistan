// SAHİBİ: reports ajanı. Başka feature bu dosyaya yazmaz.
// Uçlar (sözleşme §13; A M O P, hepsi yalnız çağıranın defteri):
//   - GET /reports/summary
//   - GET /reports/profit?range=monthly|yearly
//   - GET /reports/revenue?range=monthly|yearly
//   - GET /reports/service-distribution
// Proje kârlılığı için `GET /projects` (?limit=200 sayfalı) ve `GET /expenses` okunur.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_providers.dart';
import 'report_models.dart';

/// Hata durumunda bölüm hemen "Tekrar dene" göstermeli (GET'leri ApiClient zaten dener).
Duration? _noRetry(int retryCount, Object error) => null;

abstract class ReportsRepository {
  Future<ReportSummary> summary();
  Future<List<ProfitPoint>> profit(ReportRange range);
  Future<List<RevenuePoint>> revenue(ReportRange range);
  Future<List<ServiceShare>> serviceDistribution();
  Future<List<ProjectProfit>> projectProfitability();
}

class HttpReportsRepository implements ReportsRepository {
  HttpReportsRepository(this.api);
  final ApiClient api;

  /// Proje listesi için en çok bu kadar sayfa (200'er) okunur.
  static const int maxProjectPages = 5;

  @override
  Future<ReportSummary> summary() async =>
      ReportSummary.fromJson(await api.getMap('/reports/summary'));

  @override
  Future<List<ProfitPoint>> profit(ReportRange range) async =>
      (await api.getList(
        '/reports/profit',
        query: {'range': range.api},
      )).map(ProfitPoint.fromJson).toList();

  @override
  Future<List<RevenuePoint>> revenue(ReportRange range) async =>
      (await api.getList(
        '/reports/revenue',
        query: {'range': range.api},
      )).map(RevenuePoint.fromJson).toList();

  @override
  Future<List<ServiceShare>> serviceDistribution() async =>
      (await api.getList('/reports/service-distribution'))
          .map(ServiceShare.fromJson)
          .toList();

  @override
  Future<List<ProjectProfit>> projectProfitability() async {
    final projects = <Map<String, dynamic>>[];
    for (var page = 0; page < maxProjectPages; page++) {
      final res = await api.getPaged(
        '/projects',
        query: {'limit': 200, 'offset': projects.length},
      );
      projects.addAll(res.items);
      if (res.items.isEmpty || projects.length >= res.total) break;
    }
    final expenses = await api.getList('/expenses');
    return ProjectProfit.compute(projects, expenses);
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => HttpReportsRepository(ref.watch(apiClientProvider)),
);

final reportSummaryProvider = FutureProvider.autoDispose<ReportSummary>(
  (ref) => ref.watch(reportsRepositoryProvider).summary(),
  retry: _noRetry,
);

final reportProfitProvider = FutureProvider.autoDispose
    .family<List<ProfitPoint>, ReportRange>(
      (ref, range) => ref.watch(reportsRepositoryProvider).profit(range),
      retry: _noRetry,
    );

final reportServiceProvider = FutureProvider.autoDispose<List<ServiceShare>>(
  (ref) => ref.watch(reportsRepositoryProvider).serviceDistribution(),
  retry: _noRetry,
);

final projectProfitProvider = FutureProvider.autoDispose<List<ProjectProfit>>(
  (ref) => ref.watch(reportsRepositoryProvider).projectProfitability(),
  retry: _noRetry,
);

class ReportRangeNotifier extends Notifier<ReportRange> {
  @override
  ReportRange build() => ReportRange.monthly;
  void set(ReportRange r) => state = r;
}

final reportRangeProvider =
    NotifierProvider.autoDispose<ReportRangeNotifier, ReportRange>(
      ReportRangeNotifier.new,
    );
