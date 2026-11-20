// DEMO uçları (sözleşme §13). SAHİBİ: reports ajanı. saha: 403.
// Aylık seri BİLEREK seyrek: bazı aylar yok / sıfır (boş ay gösterimi denensin).
import '../../../core/auth/auth_models.dart';
import '../../../core/demo/demo_db.dart';
import '../../../core/demo/demo_router.dart';
import '../../../core/util/dates.dart';

/// (şimdiden geriye ay farkı) → [gelir, işletme gideri, ev gideri]; olmayan farklar seride yoktur.
const Map<int, List<num>> _monthlyDemo = {
  0: [12500, 7050.5, 12000],
  1: [8900, 6100, 12000],
  2: [5200, 4100, 12000],
  3: [0, 0, 0], // kayıtlı ama hareketsiz
  // 4 ve 5: kayıt yok
  6: [31000, 22400, 12000],
  7: [27500.75, 19800, 12000],
  9: [14000, 9900, 12000],
};

String _period(DateTime now, int back) {
  final w = Ist.wall(now);
  final ord = w.year * 12 + w.month - 1 - back;
  return '${ord ~/ 12}-${(ord % 12 + 1).toString().padLeft(2, '0')}';
}

Map<String, dynamic> _profitRow(String period, List<num> v) => {
  'period': period,
  'revenue': v[0],
  'businessExpenses': v[1],
  'homeExpenses': v[2],
  'netProfit': v[0] - v[1],
  'netProfitInclHome': v[0] - v[1] - v[2],
};

List<Map<String, dynamic>> _profit(String range) {
  final now = Ist.now();
  if (range == 'yearly') {
    final y = Ist.wall(now).year;
    return [
      _profitRow('${y - 1}', const [180000, 121000, 144000]),
      _profitRow('$y', const [99100.75, 69350.5, 120000]),
    ];
  }
  final keys = _monthlyDemo.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final k in keys) _profitRow(_period(now, k), _monthlyDemo[k]!)];
}

List<DemoRoute> reportsDemoRoutes(DemoDb db) {
  DemoResponse guard(DemoRequest req, Object Function() body) =>
      req.role == UserRole.saha
      ? DemoResponse.error(403, 'Bu işlem için yetkiniz yok.')
      : DemoResponse.json(body());
  return [
    DemoRoute(
      'GET',
      '/reports/summary',
      (req) => guard(req, () {
        final revenue = db.payments.fold<num>(
          0,
          (s, p) => s + (p['amount'] as num),
        );
        num sum(String scope) => db.expenses
            .where((e) => e['scope'] == scope)
            .fold<num>(0, (s, e) => s + (e['amount'] as num));
        final business = sum('dukkan') + sum('genel');
        final counts = <String, int>{};
        for (final o in db.offers) {
          counts.update('${o['status']}', (v) => v + 1, ifAbsent: () => 1);
        }
        final accepted = counts['Kabul Edildi'] ?? 0;
        return {
          'totalOffers': db.offers.length,
          'statusCounts': counts,
          'conversionRate': db.offers.isEmpty
              ? 0
              : double.parse(
                  (accepted * 100 / db.offers.length).toStringAsFixed(1),
                ),
          'totalRevenue': revenue,
          'activeProjects': db.projects
              .where((p) => p['stage'] != 'Tamamlandı')
              .length,
          'businessExpenses': business,
          'homeExpenses': sum('ev'),
          'expensesByScope': {
            'dukkan': sum('dukkan'),
            'genel': sum('genel'),
            'ev': sum('ev'),
          },
          'netProfit': revenue - business,
          'netProfitInclHome': revenue - business - sum('ev'),
        };
      }),
    ),
    DemoRoute(
      'GET',
      '/reports/revenue',
      (req) => guard(
        req,
        () => [
          for (final r in _profit(req.query['range'] ?? 'monthly'))
            {'period': r['period'], 'total': r['revenue']},
        ],
      ),
    ),
    DemoRoute(
      'GET',
      '/reports/profit',
      (req) => guard(req, () => _profit(req.query['range'] ?? 'monthly')),
    ),
    DemoRoute('GET', '/reports/service-distribution', (req) {
      return guard(req, () {
        final counts = <String, int>{};
        for (final o in db.offers) {
          counts.update('${o['service']}', (v) => v + 1, ifAbsent: () => 1);
        }
        return [
          for (final e in counts.entries) {'service': e.key, 'count': e.value},
        ];
      });
    }),
  ];
}
