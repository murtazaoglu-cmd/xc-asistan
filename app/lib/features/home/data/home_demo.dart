// Demo (DEMO=true) uçları: bkz. core/demo/demo_adapter.dart. Home ajanı kendi uçlarını burada günceller.
// /mobile/home yanıtı çekirdeğin DemoDb.mobileHome'undan gelir (sözleşme §2 örnek biçimi).
import '../../../core/auth/auth_models.dart';
import '../../../core/demo/demo_db.dart';
import '../../../core/demo/demo_router.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/json.dart';

List<DemoRoute> homeDemoRoutes(DemoDb db) => [
  DemoRoute('GET', '/mobile/home', (req) {
    final home = db.mobileHome(req.role);
    // Sözleşme §2: yalnız `bekliyor` durumundaki hatırlatıcılar gelir.
    final rem = asJsonMap(home['reminders']);
    home['reminders'] = {
      for (final k in const ['today', 'overdue'])
        k: asJsonList(rem[k]).where((r) => r['status'] == 'bekliyor').toList(),
    };
    return DemoResponse.json(home);
  }),
  DemoRoute('GET', '/reminders', (req) => DemoResponse.json(db.reminders)),
  DemoRoute('POST', '/reminders', (req) {
    final b = req.bodyMap;
    final title = b.strOrNull('title');
    final at = Ist.tryParse(b.strOrNull('remind_at'));
    if (title == null || at == null) {
      return DemoResponse.error(400, 'Geçersiz veya eksik değer girildi.');
    }
    final r = <String, dynamic>{
      'id': db.nextId('rem'),
      'project_id': b['project_id'],
      'title': title,
      'remind_at': db.iso(at),
      'note': b['note'],
      'status': 'bekliyor',
      'created_at': db.iso(Ist.now()),
      'owner_id': 'u-${(req.role ?? UserRole.admin).api}',
      'customer_name': null,
      'project_service': null,
      'project_code': null,
      'overdue': at.isBefore(Ist.startOfDay(Ist.now())),
    };
    db.reminders.add(r);
    return DemoResponse.json(r, status: 201);
  }),
  DemoRoute('PATCH', '/reminders/:id', (req) {
    final r = db.reminders
        .where((e) => e['id'] == req.params['id'])
        .firstOrNull;
    if (r == null) return DemoResponse.error(404, 'Hatırlatıcı bulunamadı.');
    final status = req.bodyMap.strOrNull('status');
    if (status != 'bekliyor' && status != 'tamamlandi') {
      return DemoResponse.error(400, 'Geçersiz veya eksik değer girildi.');
    }
    r['status'] = status;
    return DemoResponse.json(r);
  }),
  DemoRoute('DELETE', '/reminders/:id', (req) {
    db.reminders.removeWhere((e) => e['id'] == req.params['id']);
    return DemoResponse.json({'message': 'Hatırlatıcı silindi.'});
  }),
  // Saha fotoğraf/belge yükleme (sözleşme §12). Dosya gövdesi demoda saklanmaz.
  DemoRoute('POST', '/documents/:type/:id', (req) {
    final type = req.params['type'];
    if (type != 'offer' && type != 'project') {
      return DemoResponse.error(400, 'Geçersiz veya eksik değer girildi.');
    }
    return DemoResponse.json({
      'id': db.nextId('doc'),
      'resource_type': type,
      'resource_id': req.params['id'],
      'file_url': 'https://demo.invalid/uploads/foto.jpg',
      'file_name': 'foto.jpg',
      'uploaded_by': 'u-${(req.role ?? UserRole.admin).api}',
      'uploaded_by_name': null,
      'created_at': db.iso(Ist.now()),
    }, status: 201);
  }),
];
