// DEMO uçları (sözleşme §5). SAHİBİ: finance ajanı. saha: tümü 403.
// Sabit giderler (recurring) bellekte tutulur; ay başına bir kez uygulanır (aynı ay → 409).
import '../../../core/auth/auth_models.dart';
import '../../../core/demo/demo_db.dart';
import '../../../core/demo/demo_router.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/json.dart';
import '../../../core/util/money.dart';

DemoResponse _forbidden() =>
    DemoResponse.error(403, 'Bu işlem için yetkiniz yok.');
DemoResponse _invalid() =>
    DemoResponse.error(400, 'Geçersiz veya eksik değer girildi.');

const _methods = {'Havale', 'Nakit', 'Kredi Kartı'};
const _scopes = {'ev', 'dukkan', 'genel'};

List<DemoRoute> financeDemoRoutes(DemoDb db) {
  // Sabit gider şablonları + "bu ay uygulandı" kayıtları (id|yyyy-MM).
  final recurring = <JsonMap>[
    {
      'id': 'rec-1',
      'category': 'İşyeri kirası',
      'amount': 15000,
      'note': 'Her ayın 1\'i',
      'scope': 'dukkan',
      'active': true,
    },
    {
      'id': 'rec-2',
      'category': 'Telefon/İnternet',
      'amount': 650.5,
      'note': null,
      'scope': 'genel',
      'active': true,
    },
    {
      'id': 'rec-3',
      'category': 'Ev kirası',
      'amount': 12000,
      'note': null,
      'scope': 'ev',
      'active': true,
    },
  ];
  final applied = <String>{};

  JsonMap? projectOf(String? id) =>
      db.projects.where((e) => e['id'] == id).firstOrNull;

  void recalcPaid(String? projectId) {
    final p = projectOf(projectId);
    if (p == null) return;
    var sum = Money.zero;
    for (final x in db.payments.where((e) => e['project_id'] == projectId)) {
      sum += x.money('amount');
    }
    p['paid_amount'] = sum.toTl();
  }

  // owner_id (v16): admin/muhasebe başkasının defterine yazabilir; diğerleri sessizce kendi defterine düşer.
  String ownerFor(DemoRequest r, [Object? requested]) {
    final self = 'u-${(r.role ?? UserRole.admin).api}';
    final can = r.role == UserRole.admin || r.role == UserRole.muhasebe;
    return (can && requested is String && requested.startsWith('u-'))
        ? requested
        : self;
  }

  bool restricted(DemoRequest r) => r.role == UserRole.saha;
  bool noRecurring(DemoRequest r) =>
      r.role == UserRole.saha || r.role == UserRole.personel;

  JsonMap? byId(List<JsonMap> l, String? id) =>
      l.where((e) => e['id'] == id).firstOrNull;

  String monthKey(DateTime d) {
    final w = Ist.wall(d);
    return '${w.year}-${w.month.toString().padLeft(2, '0')}';
  }

  // POST/PATCH gövdesinden tutar (>0) okur.
  Money? positiveAmount(Object? v) {
    final m = Money.tryFromJson(v);
    return (m == null || !m.isPositive) ? null : m;
  }

  return [
    // ---- Ödemeler ----
    DemoRoute(
      'GET',
      '/projects/payments/all',
      (req) => restricted(req) ? _forbidden() : DemoResponse.json(db.payments),
    ),
    DemoRoute('GET', '/projects/:id/payments', (req) {
      if (restricted(req)) return _forbidden();
      return DemoResponse.json(
        db.payments.where((e) => e['project_id'] == req.params['id']).toList(),
      );
    }),
    DemoRoute('POST', '/projects/:id/payments', (req) {
      if (restricted(req)) return _forbidden();
      final b = req.bodyMap;
      final amount = positiveAmount(b['amount']);
      final method = b.strOrNull('method');
      if (amount == null || method == null || !_methods.contains(method)) {
        return _invalid();
      }
      final p = projectOf(req.params['id']);
      if (p == null) return DemoResponse.error(404, 'Proje bulunamadı.');
      final row = <String, dynamic>{
        'id': db.nextId('pay'),
        'project_id': p['id'],
        'amount': amount.toTl(),
        'method': method,
        'note': b['note'],
        'paid_at': b['paid_at'] ?? db.iso(Ist.now()),
        'owner_id': ownerFor(req, b['owner_id']),
      };
      db.payments.add({
        ...row,
        'customer_name': p['customer_name'],
        'project_code': p['code'],
      });
      recalcPaid(p['id'] as String?);
      return DemoResponse.json(row, status: 201);
    }),
    DemoRoute('PATCH', '/projects/payments/:id', (req) {
      if (restricted(req)) return _forbidden();
      final row = byId(db.payments, req.params['id']);
      if (row == null) return DemoResponse.error(404, 'Ödeme bulunamadı.');
      final b = req.bodyMap;
      if (b.containsKey('amount')) {
        final a = positiveAmount(b['amount']);
        if (a == null) return _invalid();
        row['amount'] = a.toTl();
      }
      if (b.containsKey('method')) {
        final m = b.strOrNull('method');
        if (m == null || !_methods.contains(m)) return _invalid();
        row['method'] = m;
      }
      if (b.containsKey('note')) row['note'] = b['note'];
      if (b.containsKey('paid_at') && b['paid_at'] != null) {
        row['paid_at'] = b['paid_at'];
      }
      if (b['owner_id'] is String) {
        row['owner_id'] = ownerFor(req, b['owner_id']);
      }
      recalcPaid(row['project_id'] as String?);
      return DemoResponse.json(row);
    }),
    DemoRoute('DELETE', '/projects/payments/:id', (req) {
      if (restricted(req)) return _forbidden();
      final row = byId(db.payments, req.params['id']);
      if (row == null) return DemoResponse.error(404, 'Ödeme bulunamadı.');
      db.payments.remove(row);
      recalcPaid(row['project_id'] as String?);
      return DemoResponse.json({'message': 'Ödeme silindi.'});
    }),

    // ---- Giderler ----
    DemoRoute(
      'GET',
      '/expenses',
      (req) => restricted(req) ? _forbidden() : DemoResponse.json(db.expenses),
    ),
    DemoRoute('POST', '/expenses', (req) {
      if (restricted(req)) return _forbidden();
      final b = req.bodyMap;
      final category = b.strOrNull('category');
      final amount = positiveAmount(b['amount']);
      final scope = b.strOrNull('scope') ?? 'genel';
      if (category == null || amount == null || !_scopes.contains(scope)) {
        return _invalid();
      }
      final projectId = b.strOrNull('project_id');
      final p = projectId == null ? null : projectOf(projectId);
      if (projectId != null && p == null) {
        return DemoResponse.error(404, 'Proje bulunamadı.');
      }
      // Kural: personel genel gider (proje bağsız) giremez.
      if (projectId == null && req.role == UserRole.personel) {
        return _forbidden();
      }
      final now = db.iso(Ist.now());
      final row = <String, dynamic>{
        'id': db.nextId('exp'),
        'project_id': projectId,
        'category': category,
        'amount': amount.toTl(),
        'note': b['note'],
        'created_at': now,
        'expense_date': b['expense_date'] ?? now,
        'scope': scope,
        'owner_id': ownerFor(req, b['owner_id']),
      };
      db.expenses.add({
        ...row,
        'customer_name': p?['customer_name'],
        'project_code': p?['code'],
      });
      return DemoResponse.json(row, status: 201);
    }),
    DemoRoute('PATCH', '/expenses/:id', (req) {
      if (restricted(req)) return _forbidden();
      final row = byId(db.expenses, req.params['id']);
      if (row == null) return DemoResponse.error(404, 'Gider bulunamadı.');
      final b = req.bodyMap;
      if (b.containsKey('category')) {
        final c = b.strOrNull('category');
        if (c == null) return _invalid();
        row['category'] = c;
      }
      if (b.containsKey('amount')) {
        final a = positiveAmount(b['amount']);
        if (a == null) return _invalid();
        row['amount'] = a.toTl();
      }
      if (b.containsKey('scope')) {
        final s = b.strOrNull('scope');
        if (s == null || !_scopes.contains(s)) return _invalid();
        row['scope'] = s;
      }
      if (b.containsKey('note')) row['note'] = b['note'];
      if (b['owner_id'] is String) {
        row['owner_id'] = ownerFor(req, b['owner_id']);
      }
      if (b.containsKey('expense_date') && b['expense_date'] != null) {
        row['expense_date'] = b['expense_date'];
      }
      return DemoResponse.json(row);
    }),
    DemoRoute('DELETE', '/expenses/:id', (req) {
      if (restricted(req)) return _forbidden();
      final row = byId(db.expenses, req.params['id']);
      if (row == null) return DemoResponse.error(404, 'Gider bulunamadı.');
      db.expenses.remove(row);
      return DemoResponse.json({'message': 'Gider silindi.'});
    }),
    DemoRoute('GET', '/projects/:id/expenses', (req) {
      if (restricted(req)) return _forbidden();
      return DemoResponse.json(
        db.expenses.where((e) => e['project_id'] == req.params['id']).toList(),
      );
    }),

    // ---- Sabit giderler (A M O) ----
    DemoRoute(
      'GET',
      '/recurring-expenses',
      (req) => noRecurring(req) ? _forbidden() : DemoResponse.json(recurring),
    ),
    DemoRoute('POST', '/recurring-expenses', (req) {
      if (noRecurring(req)) return _forbidden();
      final b = req.bodyMap;
      final category = b.strOrNull('category');
      final amount = positiveAmount(b['amount']);
      final scope = b.strOrNull('scope') ?? 'genel';
      if (category == null || amount == null || !_scopes.contains(scope)) {
        return _invalid();
      }
      final row = <String, dynamic>{
        'id': db.nextId('rec'),
        'category': category,
        'amount': amount.toTl(),
        'note': b['note'],
        'scope': scope,
        'active': true,
      };
      recurring.add(row);
      return DemoResponse.json(row, status: 201);
    }),
    DemoRoute('PATCH', '/recurring-expenses/:id', (req) {
      if (noRecurring(req)) return _forbidden();
      final row = byId(recurring, req.params['id']);
      if (row == null) return DemoResponse.error(404, 'Kayıt bulunamadı.');
      final b = req.bodyMap;
      if (b.containsKey('category')) {
        final c = b.strOrNull('category');
        if (c == null) return _invalid();
        row['category'] = c;
      }
      if (b.containsKey('amount')) {
        final a = positiveAmount(b['amount']);
        if (a == null) return _invalid();
        row['amount'] = a.toTl();
      }
      if (b.containsKey('scope')) {
        final s = b.strOrNull('scope');
        if (s == null || !_scopes.contains(s)) return _invalid();
        row['scope'] = s;
      }
      if (b.containsKey('note')) row['note'] = b['note'];
      if (b.containsKey('active')) row['active'] = b.boolOr('active', true);
      return DemoResponse.json(row);
    }),
    DemoRoute('DELETE', '/recurring-expenses/:id', (req) {
      if (noRecurring(req)) return _forbidden();
      final row = byId(recurring, req.params['id']);
      if (row == null) return DemoResponse.error(404, 'Kayıt bulunamadı.');
      recurring.remove(row);
      return DemoResponse.json({'message': 'Silindi.'});
    }),
    DemoRoute('POST', '/recurring-expenses/:id/apply', (req) {
      if (noRecurring(req)) return _forbidden();
      final row = byId(recurring, req.params['id']);
      if (row == null) return DemoResponse.error(404, 'Kayıt bulunamadı.');
      final key = '${row['id']}|${monthKey(Ist.now())}';
      if (applied.contains(key)) {
        return DemoResponse.error(409, 'Bu ay zaten eklenmiş.');
      }
      applied.add(key);
      final now = db.iso(Ist.now());
      final exp = <String, dynamic>{
        'id': db.nextId('exp'),
        'project_id': null,
        'category': row['category'],
        'amount': row['amount'],
        'note': row['note'],
        'created_at': now,
        'expense_date': now,
        'scope': row['scope'],
        'owner_id': 'u-${(req.role ?? UserRole.admin).api}',
        'customer_name': null,
        'project_code': null,
      };
      db.expenses.add(exp);
      return DemoResponse.json(exp, status: 201);
    }),
  ];
}
