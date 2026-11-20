// DEMO uçları (sözleşme §11). SAHİBİ: stock ajanı. A M O; personel/saha: 403.
import '../../../core/auth/auth_models.dart';
import '../../../core/demo/demo_db.dart';
import '../../../core/demo/demo_router.dart';
import '../../../core/util/json.dart';

DemoResponse _forbidden() =>
    DemoResponse.error(403, 'Bu işlem için yetkiniz yok.');

bool _allowed(DemoRequest req) {
  final r = req.role ?? UserRole.admin;
  return r != UserRole.saha && r != UserRole.personel;
}

DemoResponse _bad() =>
    DemoResponse.error(400, 'Geçersiz veya eksik değer girildi.');

bool _nonNegative(Object? v) =>
    v == null ||
    (v is num && v >= 0) ||
    (v is String && (num.tryParse(v) ?? -1) >= 0);

List<DemoRoute> stockDemoRoutes(DemoDb db) => [
  DemoRoute(
    'GET',
    '/materials',
    (req) => _allowed(req) ? DemoResponse.json(db.materials) : _forbidden(),
  ),
  DemoRoute('POST', '/materials', (req) {
    if (!_allowed(req)) return _forbidden();
    final b = req.bodyMap;
    final name = b.strOrNull('name');
    if (name == null ||
        !_nonNegative(b['stock_quantity']) ||
        !_nonNegative(b['low_stock_threshold'])) {
      return _bad();
    }
    final row = <String, dynamic>{
      'id': db.nextId('mat'),
      'name': name,
      'unit': b.strOrNull('unit') ?? 'adet',
      'stock_quantity': b['stock_quantity'] ?? 0,
      'low_stock_threshold': b['low_stock_threshold'] ?? 5,
      'note': b.strOrNull('note'),
      'updated_at': db.iso(DateTime.now()),
      'owner_id': 'u-admin',
    };
    db.materials.add(row);
    return DemoResponse.json(row, status: 201);
  }),
  DemoRoute('PATCH', '/materials/:id', (req) {
    if (!_allowed(req)) return _forbidden();
    final m = db.materials
        .where((e) => e['id'] == req.params['id'])
        .firstOrNull;
    if (m == null) return DemoResponse.error(404, 'Malzeme bulunamadı.');
    final b = req.bodyMap;
    if (!_nonNegative(b['stock_quantity']) ||
        !_nonNegative(b['low_stock_threshold'])) {
      return _bad();
    }
    if (b.containsKey('name') && b.strOrNull('name') == null) return _bad();
    for (final k in const [
      'name',
      'unit',
      'stock_quantity',
      'low_stock_threshold',
      'note',
    ]) {
      if (b.containsKey(k)) m[k] = b[k];
    }
    m['updated_at'] = db.iso(DateTime.now());
    return DemoResponse.json(m);
  }),
  DemoRoute('DELETE', '/materials/:id', (req) {
    if (!_allowed(req)) return _forbidden();
    final before = db.materials.length;
    db.materials.removeWhere((e) => e['id'] == req.params['id']);
    if (before == db.materials.length) {
      return DemoResponse.error(404, 'Malzeme bulunamadı.');
    }
    return DemoResponse.json({'message': 'Malzeme silindi.'});
  }),
];
