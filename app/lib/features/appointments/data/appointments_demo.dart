// DEMO uçları (sözleşme §9). SAHİBİ: appointments ajanı (gerekirse genişletir).
import '../../../core/auth/auth_models.dart';
import '../../../core/demo/demo_db.dart';
import '../../../core/demo/demo_router.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/json.dart';

List<DemoRoute> appointmentsDemoRoutes(DemoDb db) => [
  DemoRoute('GET', '/appointments', (req) {
    var list = db.appointmentsFor(req.role ?? UserRole.admin);
    final from = Ist.tryParse(req.query['from']);
    final to = Ist.tryParse(req.query['to']);
    final status = req.query['status'];
    final assigned = req.query['assigned_user_id'];
    list =
        list.where((a) {
          final t = Ist.tryParse(a['scheduled_at'] as String?);
          if (t == null) return false;
          if (from != null && t.isBefore(from)) return false;
          if (to != null && !t.isBefore(to)) return false;
          if (status != null && a['status'] != status) return false;
          if (assigned != null) {
            final me = 'u-${(req.role ?? UserRole.admin).api}';
            if (a['assigned_user_id'] != (assigned == 'me' ? me : assigned))
              return false;
          }
          return true;
        }).toList()..sort(
          (a, b) => (a['scheduled_at'] as String).compareTo(
            b['scheduled_at'] as String,
          ),
        );
    return DemoResponse.json(list);
  }),
  DemoRoute('GET', '/appointments/:id', (req) {
    final a = db.appointments
        .where((e) => e['id'] == req.params['id'])
        .firstOrNull;
    return a == null
        ? DemoResponse.error(404, 'Randevu bulunamadı.')
        : DemoResponse.json(a);
  }),
  DemoRoute('POST', '/appointments', (req) {
    if (req.role == UserRole.saha) {
      return DemoResponse.error(403, 'Bu işlem için yetkiniz yok.');
    }
    final b = req.bodyMap;
    final type = b.strOrNull('type');
    final at = Ist.tryParse(b.strOrNull('scheduled_at'));
    if (type == null || type.length > 40 || at == null) {
      return DemoResponse.error(400, 'Geçersiz veya eksik değer girildi.');
    }
    final me = 'u-${(req.role ?? UserRole.admin).api}';
    final assigned = b.strOrNull('assigned_user_id') ?? me;
    final a = <String, dynamic>{
      'id': db.nextId('apt'),
      'offer_id': b['offer_id'],
      'project_id': b['project_id'],
      'type': type,
      'scheduled_at': db.iso(at),
      'assigned_user_id': assigned,
      'assigned_user_name': _userName(db, assigned),
      'notes': b['notes'],
      'status': 'beklemede',
      'owner_id': me,
      'customer_name': b['customer_name'],
      'customer_phone': b['customer_phone'],
      'address': b['address'],
      'lat': b['lat'],
      'lng': b['lng'],
      'service': null,
      'offer_code': null,
      'project_code': null,
      'offer_name': null,
      'offer_phone': null,
      'offer_service': null,
      'project_customer': null,
    };
    _resolveLinks(db, a);
    db.appointments.add(a);
    return DemoResponse.json(a, status: 201);
  }),
  DemoRoute('PATCH', '/appointments/:id', (req) {
    final a = db.appointments
        .where((e) => e['id'] == req.params['id'])
        .firstOrNull;
    if (a == null) return DemoResponse.error(404, 'Randevu bulunamadı.');
    final saha = req.role == UserRole.saha;
    final body = req.bodyMap;
    // Sözleşme: saha yalnız status, notes, scheduled_at değiştirebilir.
    if (saha && body.keys.any((k) => !_fieldAllowed.contains(k))) {
      return DemoResponse.error(403, 'Bu işlem için yetkiniz yok.');
    }
    for (final e in body.entries) {
      if (e.key == 'scheduled_at') {
        final t = Ist.tryParse(e.value as String?);
        if (t == null) {
          return DemoResponse.error(400, 'Geçersiz veya eksik değer girildi.');
        }
        a[e.key] = db.iso(t);
      } else if (e.key == 'type' &&
          (e.value is! String || (e.value as String).length > 40)) {
        return DemoResponse.error(400, 'Geçersiz veya eksik değer girildi.');
      } else {
        a[e.key] = e.value;
      }
    }
    if (body.containsKey('assigned_user_id')) {
      a['assigned_user_name'] = _userName(db, a['assigned_user_id'] as String?);
    }
    if (body.containsKey('offer_id') || body.containsKey('project_id')) {
      _resolveLinks(db, a);
    }
    return DemoResponse.json(a);
  }),
  DemoRoute('DELETE', '/appointments/:id', (req) {
    if (req.role == UserRole.saha) {
      return DemoResponse.error(403, 'Bu işlem için yetkiniz yok.');
    }
    final before = db.appointments.length;
    db.appointments.removeWhere((e) => e['id'] == req.params['id']);
    if (db.appointments.length == before) {
      return DemoResponse.error(404, 'Randevu bulunamadı.');
    }
    return DemoResponse.json({'message': 'Randevu silindi.'});
  }),
];

const _fieldAllowed = {'status', 'notes', 'scheduled_at'};

String? _userName(DemoDb db, String? id) {
  if (id == null || !id.startsWith('u-')) return null;
  final r = UserRole.fromApi(id.substring(2));
  return r == null ? null : db.userFor(r)['name'] as String?;
}

/// Bağlı teklif/proje varsa kod ve eksik müşteri bilgilerini doldurur (sözleşme §9 çözümleme sırası).
void _resolveLinks(DemoDb db, JsonMap a) {
  final offer = db.offers.where((o) => o['id'] == a['offer_id']).firstOrNull;
  final project = db.projects
      .where((p) => p['id'] == a['project_id'])
      .firstOrNull;
  a['offer_code'] = offer?['code'];
  a['offer_name'] = offer?['name'];
  a['offer_phone'] = offer?['phone'];
  a['offer_service'] = offer?['service'];
  a['project_code'] = project?['code'];
  a['project_customer'] = project?['customer_name'];
  a['service'] = offer?['service'] ?? project?['service'] ?? a['service'];
  a['customer_name'] ??= offer?['name'] ?? project?['customer_name'];
  a['customer_phone'] ??= offer?['phone'] ?? project?['customer_phone'];
  if (a['address'] == null &&
      (offer?['address'] ?? project?['address']) != null) {
    final src = offer?['address'] != null ? offer! : project!;
    a['address'] = src['address'];
    a['lat'] = src['lat'];
    a['lng'] = src['lng'];
  }
}
