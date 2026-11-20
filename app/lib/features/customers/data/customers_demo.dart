// DEMO uçları (sözleşme §6-§7). SAHİBİ: customers ajanı. personel/saha: 403.
// Elle eklenen müşteriler DemoDb'ye dokunmadan burada (DemoDb'ye bağlı) tutulur.
import '../../../core/auth/auth_models.dart';
import '../../../core/demo/demo_db.dart';
import '../../../core/demo/demo_router.dart';
import '../../../core/util/json.dart';
import '../../../core/util/phone.dart';
import '../../jobs/data/jobs_demo.dart';

final Expando<List<JsonMap>> _manual = Expando<List<JsonMap>>(
  'manualCustomers',
);

List<JsonMap> _manualOf(DemoDb db) => _manual[db] ??= <JsonMap>[];

DemoResponse _forbidden() =>
    DemoResponse.error(403, 'Bu işlem için yetkiniz yok.');

bool _allowed(DemoRequest req) {
  final role = req.role ?? UserRole.admin;
  return role != UserRole.saha && role != UserRole.personel;
}

/// Tekliflerden türeyen müşteriler (telefon anahtarına göre birleşik) + elle eklenenler.
List<JsonMap> _customers(DemoDb db) {
  final byKey = <String, JsonMap>{};
  for (final o in db.offers) {
    final key = PhoneUtil.phoneKey(o['phone'] as String?);
    final projects = db.projects.where(
      (p) =>
          PhoneUtil.phoneKey(p['customer_phone'] as String?) == key ||
          p['customer_name'] == o['name'],
    );
    final paid = projects.fold<num>(0, (s, p) => s + (p['paid_amount'] as num));
    final contracted = projects.fold<num>(
      0,
      (s, p) => s + (p['total_amount'] as num),
    );
    final prev = byKey[key];
    byKey[key] = {
      'phone_key': key,
      'name': o['name'],
      'email': o['email'],
      'phone': o['phone'],
      'region': o['region'],
      'address': o['address'],
      'lat': o['lat'],
      'lng': o['lng'],
      'offer_count': ((prev?['offer_count'] as int?) ?? 0) + 1,
      'first_contact': o['created_at'],
      'last_contact': prev?['last_contact'] ?? o['created_at'],
      'project_count': projects.length,
      'total_contracted': contracted,
      'total_paid': paid,
    };
  }
  for (final m in _manualOf(db)) {
    byKey.putIfAbsent(m['phone_key'] as String, () => m);
  }
  final list = byKey.values.toList()
    ..sort(
      (a, b) => '${b['last_contact']}'.compareTo(
        '${a['last_contact']}',
      ), // son temas ↓
    );
  return list;
}

bool _validEmail(String s) =>
    RegExp(r'^[^\s@,<>;]+@[^\s@,<>;]+\.[^\s@,<>;]{2,}$').hasMatch(s);

List<DemoRoute> customersDemoRoutes(DemoDb db) => [
  DemoRoute('GET', '/customers', (req) {
    if (!_allowed(req)) return _forbidden();
    return pagedList(_customers(db), req, (c, q) {
      final digits = PhoneUtil.digits(q);
      if (digits.length >= 3 &&
          PhoneUtil.digits(c['phone']?.toString()).contains(digits)) {
        return true;
      }
      return [
        'name',
        'phone',
        'email',
        'region',
        'address',
      ].any((k) => (c[k]?.toString().toLowerCase() ?? '').contains(q));
    });
  }),
  DemoRoute('POST', '/customers', (req) {
    if (!_allowed(req)) return _forbidden();
    final b = req.bodyMap;
    final name = b.strOrNull('name');
    final phone = b.strOrNull('phone');
    if (name == null || phone == null || PhoneUtil.digits(phone).length < 10) {
      return DemoResponse.error(400, 'Geçersiz veya eksik değer girildi.');
    }
    final email = b.strOrNull('email');
    if (email != null && !_validEmail(email)) {
      return DemoResponse.error(400, 'Geçerli bir e-posta adresi girin.');
    }
    final key = PhoneUtil.phoneKey(phone);
    if (_customers(db).any((c) => c['phone_key'] == key)) {
      return DemoResponse.error(
        409,
        'Bu telefon numarasıyla kayıtlı bir müşteri var.',
      );
    }
    final now = db.iso(DateTime.now());
    final row = <String, dynamic>{
      'phone_key': key,
      'name': name,
      'email': email,
      'phone': phone,
      'region': b.strOrNull('region'),
      'address': b.strOrNull('address'),
      'note': b.strOrNull('note'),
      'lat': b.doubleOrNull('lat'),
      'lng': b.doubleOrNull('lng'),
      'offer_count': 0,
      'first_contact': now,
      'last_contact': now,
      'project_count': 0,
      'total_contracted': 0,
      'total_paid': 0,
    };
    _manualOf(db).add(row);
    return DemoResponse.json(row, status: 201);
  }),
  DemoRoute('GET', '/customers/:phoneKey', (req) {
    if (!_allowed(req)) return _forbidden();
    final key = req.params['phoneKey']!;
    return DemoResponse.json({
      'offers': db.offers
          .where((o) => PhoneUtil.phoneKey(o['phone'] as String?) == key)
          .toList(),
      'projects': db.projects
          .where(
            (p) => PhoneUtil.phoneKey(p['customer_phone'] as String?) == key,
          )
          .toList(),
    });
  }),
  DemoRoute('PATCH', '/customers/:phoneKey', (req) {
    if (!_allowed(req)) return _forbidden();
    final m = _manualOf(db)
        .where((c) => c['phone_key'] == req.params['phoneKey'])
        .firstOrNull;
    // Tekliften türeyen müşteri düzenlenmez (sözleşme): 404.
    if (m == null) return DemoResponse.error(404, 'Müşteri bulunamadı.');
    final b = req.bodyMap;
    if (b.containsKey('name') && b.strOrNull('name') == null) {
      return DemoResponse.error(400, 'Geçersiz veya eksik değer girildi.');
    }
    final email = b.strOrNull('email');
    if (email != null && !_validEmail(email)) {
      return DemoResponse.error(400, 'Geçerli bir e-posta adresi girin.');
    }
    for (final k in const [
      'name',
      'email',
      'region',
      'note',
      'address',
      'lat',
      'lng',
    ]) {
      if (b.containsKey(k)) m[k] = b[k] is String ? b.strOrNull(k) : b[k];
    }
    return DemoResponse.json(m);
  }),
  DemoRoute('DELETE', '/customers/:phoneKey', (req) {
    if (!_allowed(req)) return _forbidden();
    final list = _manualOf(db);
    final before = list.length;
    list.removeWhere((c) => c['phone_key'] == req.params['phoneKey']);
    // Kapsam dışı/türetilmiş müşteride sessizce hiçbir şey silinmez (sözleşme).
    return DemoResponse.json({
      'message': before == list.length
          ? 'Silinecek kayıt yok.'
          : 'Müşteri silindi.',
    });
  }),
];
