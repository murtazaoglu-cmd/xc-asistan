// DEMO uçları (sözleşme §3-4, §12). SAHİBİ: jobs ajanı (gerekirse genişletir).
// Durum bellektedir (uygulama kapanınca sıfırlanır); biçimler sözleşme örnekleriyle aynıdır.
import 'package:dio/dio.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/demo/demo_db.dart';
import '../../../core/demo/demo_router.dart';
import '../../../core/util/domain_enums.dart';
import '../../../core/util/json.dart';
import '../../../core/util/money.dart';
import 'jobs_models.dart';
import 'jobs_project_models.dart';

DemoResponse _forbidden() =>
    DemoResponse.error(403, 'Bu işlem için yetkiniz yok.');

DemoResponse _invalid() =>
    DemoResponse.error(400, 'Geçersiz veya eksik değer girildi.');

/// q / limit / offset / X-Total-Count davranışı (sözleşme §6).
DemoResponse pagedList(
  List<JsonMap> all,
  DemoRequest req,
  bool Function(JsonMap, String) matches,
) {
  var list = all;
  final q = req.query['q']?.toLowerCase();
  if (q != null && q.isNotEmpty) {
    list = list.where((e) => matches(e, q)).toList();
  }
  final hasPaging =
      req.query.containsKey('limit') || (q != null && q.isNotEmpty);
  final total = list.length;
  final offset = int.tryParse(req.query['offset'] ?? '') ?? 0;
  final limit =
      int.tryParse(req.query['limit'] ?? '') ??
      (req.query.containsKey('offset') ? 50 : total);
  list = list.skip(offset).take(limit).toList();
  return DemoResponse.json(
    list,
    headers: hasPaging ? {'X-Total-Count': '$total'} : const {},
  );
}

List<String> _ids(JsonMap body) => [
  for (final v in (body['ids'] is List ? body['ids'] as List : const []))
    if (v != null) v.toString(),
];

bool _isFinanceRole(UserRole? r) =>
    r == UserRole.admin ||
    r == UserRole.muhasebe ||
    r == UserRole.ortak ||
    r == UserRole.personel;

List<DemoRoute> jobsDemoRoutes(DemoDb db) {
  // ---- Bu özelliğe ait bellek içi durum ----
  final tasks = <String, List<JsonMap>>{
    'prj-1': [
      {
        'id': 'tsk-1',
        'project_id': 'prj-1',
        'title': 'Ölçü al',
        'status': 'tamamlandi',
        'assigned_user_id': null,
      },
      {
        'id': 'tsk-2',
        'project_id': 'prj-1',
        'title': 'Malzemeyi hazırla',
        'status': 'devam_ediyor',
        'assigned_user_id': null,
      },
      {
        'id': 'tsk-3',
        'project_id': 'prj-1',
        'title': 'Montajı yap',
        'status': 'bekliyor',
        'assigned_user_id': null,
      },
    ],
  };
  final extras = <String, List<JsonMap>>{};
  final docs = <String, List<JsonMap>>{}; // 'project:id' / 'offer:id'
  final shares = <String, List<JsonMap>>{};
  final activity = <String, List<JsonMap>>{};
  final sendCount = <String, int>{};

  JsonMap? offerOf(String id) =>
      db.offers.where((e) => e['id'] == id).firstOrNull;
  JsonMap? projectOf(String id) =>
      db.projects.where((e) => e['id'] == id).firstOrNull;

  void log(String type, String id, String action, String? details) {
    (activity['$type:$id'] ??= []).insert(0, {
      'id': db.nextId('act'),
      'resource_type': type,
      'resource_id': id,
      'user_id': 'u-admin',
      'action': action,
      'details': details,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'user_name': 'Yönetici',
    });
  }

  num tl(Money m) => m.kurus / 100;

  JsonMap buildQuote(String offerId, List<QuoteItem> items) {
    final t = QuoteMath.compute(items);
    return {
      'id': db.nextId('q'),
      'offer_id': offerId,
      'items': items.map((e) => e.toJson()).toList(),
      'subtotal': tl(t.subtotal),
      'tax': tl(t.tax),
      'total': tl(t.total),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'sent_via_whatsapp_at': null,
      'sent_via_email_at': null,
      'last_send_status': null,
      'last_send_at': null,
      'last_send_error': null,
    };
  }

  JsonMap projectRow(JsonMap p, UserRole? role) {
    final paid = db.payments
        .where((x) => x['project_id'] == p['id'])
        .fold<num>(0, (s, x) => s + (x['amount'] as num));
    final row = Map<String, dynamic>.of(p);
    row['paid_amount'] = paid;
    if (role != UserRole.saha) {
      final extra = (extras[p['id']] ?? const <JsonMap>[]).fold<num>(
        0,
        (s, e) => s + (e['amount'] as num),
      );
      row['balance'] = ((p['total_amount'] as num) + extra - paid).clamp(
        0,
        double.infinity,
      );
    }
    if (role == UserRole.saha) row.remove('total_amount');
    return row;
  }

  JsonMap createProjectFromOffer(JsonMap o) {
    final existing = db.projects
        .where((p) => p['offer_id'] == o['id'])
        .firstOrNull;
    if (existing != null) return existing;
    final n = 500 + db.projects.length + 1;
    final q = o['quote'];
    final p = <String, dynamic>{
      'id': db.nextId('prj'),
      'code': 'PRJ-$n',
      'offer_id': o['id'],
      'customer_name': o['name'],
      'customer_phone': o['phone'],
      'service': o['service'],
      'stage': 'Malzeme Temini',
      'total_amount': q is Map ? q['total'] : 0,
      'assigned_team': null,
      'start_date': DateTime.now().toUtc().toIso8601String(),
      'end_date': null,
      'notes': null,
      'owner_id': 'u-admin',
      'address': o['address'],
      'lat': o['lat'],
      'lng': o['lng'],
      'paid_amount': 0,
    };
    db.projects.insert(0, p);
    return p;
  }

  return [
    // ---------------- Teklifler ----------------
    DemoRoute('POST', '/offers', (req) {
      final b = req.bodyMap;
      final name = b.strOrNull('name');
      final phone = b.strOrNull('phone');
      final service = b.strOrNull('service');
      if (name == null || phone == null || service == null) return _invalid();
      final email = b.strOrNull('email');
      if (email != null && OfferValidators.email(email) != null) {
        return DemoResponse.error(400, 'Geçerli bir e-posta adresi girin.');
      }
      final id = db.nextId('off');
      final n = 1000 + db.offers.length + 1;
      final now = DateTime.now().toUtc().toIso8601String();
      db.offers.insert(0, {
        'id': id,
        'code': 'OFR-$n',
        'tracking_code': 'XCY-DEMO$n',
        'name': name,
        'phone': phone,
        'email': email,
        'service': service,
        'region': b.strOrNull('region'),
        'message': b.strOrNull('message'),
        'notes': null,
        'photo_urls': <String>[],
        'status': 'Yeni',
        'source': 'admin',
        'source_site': 'controlx',
        'owner_id': 'u-admin',
        'address': b.strOrNull('address'),
        'lat': null,
        'lng': null,
        'created_at': now,
        'updated_at': now,
        'quote': null,
        'quote_items': null,
        'quote_total': null,
      });
      return DemoResponse.json({
        'message': 'Teklif talebiniz alındı.',
        'id': id,
        'code': 'OFR-$n',
        'trackingCode': 'XCY-DEMO$n',
        'trackingUrl': 'https://demo.example/teklif-takip/XCY-DEMO$n',
      }, status: 201);
    }, public: true),
    // Toplu uçlar ':id' rotalarından ÖNCE (ilk eşleşen kazanır). Sunucu gibi: erişimsizi sessizce atlar, sayı döner.
    DemoRoute('PATCH', '/offers/bulk-status', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final ids = _ids(req.bodyMap);
      final s = req.bodyMap.strOrNull('status');
      if (ids.isEmpty || s == null || OfferStatus.fromApi(s) == null) {
        return DemoResponse.error(
          400,
          'Geçerli id listesi ve durum zorunludur.',
        );
      }
      var updated = 0;
      for (final id in ids) {
        final o = offerOf(id);
        if (o == null) continue;
        if (o['status'] == 'Kabul Edildi' &&
            s != 'Kabul Edildi' &&
            req.role != UserRole.admin) {
          continue;
        }
        o['status'] = s;
        log('offer', id, 'durum_degisti', '$s (toplu)');
        if (s == 'Kabul Edildi') createProjectFromOffer(o);
        updated++;
      }
      return DemoResponse.json({
        'message': '$updated teklif güncellendi.',
        'updated': updated,
      });
    }),
    DemoRoute('DELETE', '/offers/bulk', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final ids = _ids(req.bodyMap);
      if (ids.isEmpty) {
        return DemoResponse.error(400, 'Geçerli id listesi zorunludur.');
      }
      var deleted = 0;
      for (final id in ids) {
        final o = offerOf(id);
        if (o == null) continue;
        final owner = o['owner_id'];
        final mine = owner == null || owner == 'u-${req.role?.api}';
        if (req.role != UserRole.admin && !mine) continue;
        db.offers.remove(o);
        deleted++;
      }
      return DemoResponse.json({
        'message': '$deleted teklif silindi.',
        'deleted': deleted,
      });
    }),
    DemoRoute('GET', '/offers', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final status = req.query['status'];
      final base = db.offers
          .where((o) => status == null || o['status'] == status)
          .toList();
      return pagedList(
        base,
        req,
        (o, q) => [
          'name',
          'phone',
          'email',
          'code',
          'service',
          'region',
          'address',
        ].any((k) => (o[k]?.toString().toLowerCase() ?? '').contains(q)),
      );
    }),
    DemoRoute('GET', '/offers/:id', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final o = offerOf(req.params['id']!);
      return o == null
          ? DemoResponse.error(404, 'Teklif bulunamadı.')
          : DemoResponse.json(o);
    }),
    DemoRoute('PATCH', '/offers/:id/status', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final o = offerOf(req.params['id']!);
      if (o == null) return DemoResponse.error(404, 'Teklif bulunamadı.');
      final s = req.bodyMap.strOrNull('status');
      if (s == null || OfferStatus.fromApi(s) == null) {
        return DemoResponse.error(400, 'Geçersiz durum.');
      }
      if (o['status'] == 'Kabul Edildi' &&
          s != 'Kabul Edildi' &&
          req.role != UserRole.admin) {
        return DemoResponse.error(
          409,
          'Kabul edilmiş teklifin durumu değiştirilemez (yalnızca yönetici düzeltebilir).',
        );
      }
      o['status'] = s;
      log('offer', o['id'] as String, 'durum_degisti', s);
      if (s == 'Kabul Edildi') createProjectFromOffer(o);
      // PATCH yanıtı `quote` taşımaz (sözleşme: güncel kayıt satırı).
      return DemoResponse.json(Map<String, dynamic>.of(o)..remove('quote'));
    }),
    DemoRoute('PATCH', '/offers/:id', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final o = offerOf(req.params['id']!);
      if (o == null) return DemoResponse.error(404, 'Teklif bulunamadı.');
      final b = req.bodyMap;
      final email = b.strOrNull('email');
      if (email != null && OfferValidators.email(email) != null) {
        return DemoResponse.error(400, 'Geçerli bir e-posta adresi girin.');
      }
      for (final k in [
        'name',
        'phone',
        'email',
        'service',
        'region',
        'message',
        'notes',
        'address',
      ]) {
        if (b.containsKey(k)) o[k] = b.strOrNull(k);
      }
      log('offer', o['id'] as String, 'duzenlendi', null);
      return DemoResponse.json(Map<String, dynamic>.of(o)..remove('quote'));
    }),
    DemoRoute('DELETE', '/offers/:id', (req) {
      if (req.role == UserRole.saha || req.role == UserRole.muhasebe) {
        return _forbidden();
      }
      final o = offerOf(req.params['id']!);
      if (o == null) return DemoResponse.error(404, 'Teklif bulunamadı.');
      db.offers.remove(o);
      return DemoResponse.json({'message': 'Teklif silindi.'});
    }),

    // ---------------- Teklif hazırlama / gönderme ----------------
    DemoRoute('POST', '/quotes/:offerId', (req) {
      if (req.role == UserRole.saha || req.role == UserRole.personel) {
        return _forbidden();
      }
      final o = offerOf(req.params['offerId']!);
      if (o == null) return DemoResponse.error(404, 'Teklif bulunamadı.');
      final items = req.bodyMap.list('items').map(QuoteItem.fromJson).toList();
      final err = QuoteMath.validate(items);
      if (err != null) return DemoResponse.error(400, err);
      final q = buildQuote(o['id'] as String, items);
      o['quote'] = q;
      o['quote_total'] = q['total'];
      if (const [
        'Yeni',
        'İncelendi',
        'Keşif Planlandı',
      ].contains(o['status'])) {
        o['status'] = 'Teklif Verildi';
      }
      return DemoResponse.json(q, status: 201);
    }),
    // Gönderim: sırayla 207 (kısmen) → 200 (gönderildi) → 502 (gönderilemedi) döner;
    // arayüzün üç sonucu da dürüstçe gösterdiği DEMO'da denenebilsin.
    DemoRoute('POST', '/quotes/:offerId/send', (req) {
      if (req.role == UserRole.saha || req.role == UserRole.personel) {
        return _forbidden();
      }
      final o = offerOf(req.params['offerId']!);
      if (o == null) return DemoResponse.error(404, 'Teklif bulunamadı.');
      final q = o['quote'];
      if (q is! Map) {
        return DemoResponse.error(400, 'Önce bir teklif hazırlanmalı.');
      }
      final id = o['id'] as String;
      final n = sendCount[id] = (sendCount[id] ?? 0) + 1;
      final phone = (o['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      final wa =
          'https://wa.me/90${phone.length > 10 ? phone.substring(phone.length - 10) : phone}?text=Merhaba';
      final pdf =
          'https://api.controlx.com.tr/uploads/teklif-${o['code']}.pdf?exp=1795000000&sig=demo';
      final mode = (n - 1) % 3;
      final nowIso = DateTime.now().toUtc().toIso8601String();
      if (mode == 1) {
        q['last_send_status'] = 'gonderildi';
        q['last_send_at'] = nowIso;
        q['last_send_error'] = null;
        return DemoResponse.json({
          'sent': true,
          'channel': 'whatsapp,email',
          'status': 'gonderildi',
          'error': null,
          'channels': {
            'whatsapp': {'sent': true, 'error': null},
            'email': {'sent': true, 'skipped': false, 'error': null},
          },
          'message': 'Gönderim tamamlandı.',
          'pdfUrl': pdf,
          'whatsappUrl': wa,
        });
      }
      if (mode == 2) {
        q['last_send_status'] = 'basarisiz';
        q['last_send_at'] = nowIso;
        q['last_send_error'] = 'WhatsApp: WhatsApp 24 saat kuralı.';
        return DemoResponse.json({
          'sent': false,
          'channel': null,
          'status': 'basarisiz',
          'error': 'WhatsApp: WhatsApp 24 saat kuralı: müşteri son 24 saatte yazmadı.',
          'channels': {
            'whatsapp': {
              'sent': false,
              'error':
                  'WhatsApp 24 saat kuralı: müşteri son 24 saatte yazmadı.',
            },
            'email': {
              'sent': false,
              'skipped': true,
              'error': 'Müşterinin e-posta adresi yok.',
            },
          },
          'message': 'Teklif gönderilemedi.',
          'pdfUrl': pdf,
          'whatsappUrl': wa,
        }, status: 502);
      }
      q['last_send_status'] = 'kismen';
      q['last_send_at'] = nowIso;
      q['last_send_error'] = 'WhatsApp: WhatsApp 24 saat kuralı.';
      q['sent_via_email_at'] = nowIso;
      return DemoResponse.json({
        'sent': true,
        'channel': 'email',
        'status': 'kismen',
        'error':
            'WhatsApp: WhatsApp 24 saat kuralı: müşteri son 24 saatte yazmadı.',
        'channels': {
          'whatsapp': {
            'sent': false,
            'error': 'WhatsApp 24 saat kuralı: müşteri son 24 saatte yazmadı.',
          },
          'email': {'sent': true, 'skipped': false, 'error': null},
        },
        'message': 'Teklif kısmen gönderildi.',
        'pdfUrl': pdf,
        'whatsappUrl': wa,
      }, status: 207);
    }),
    DemoRoute('GET', '/quote-templates', (req) {
      if (req.role != UserRole.admin && req.role != UserRole.muhasebe) {
        return _forbidden();
      }
      return DemoResponse.json([
        {
          'id': 'tpl-1',
          'name': 'Standart hizmet paketi',
          'items': [
            {'desc': 'Malzeme', 'qty': 1, 'price': 4000, 'vatIncluded': false},
            {'desc': 'İşçilik', 'qty': 1, 'price': 1500, 'vatIncluded': false},
          ],
        },
        {
          'id': 'tpl-2',
          'name': 'Bakım (KDV dahil)',
          'items': [
            {
              'desc': 'Periyodik bakım',
              'qty': 1,
              'price': 1200,
              'vatIncluded': true,
            },
          ],
        },
      ]);
    }),

    // ---------------- Projeler ----------------
    DemoRoute('GET', '/projects', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      return pagedList(
        db.projects.map((p) => projectRow(p, req.role)).toList(),
        req,
        (p, q) => [
          'customer_name',
          'code',
          'service',
          'address',
          'notes',
        ].any((k) => (p[k]?.toString().toLowerCase() ?? '').contains(q)),
      );
    }),
    DemoRoute('POST', '/projects', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final b = req.bodyMap;
      final name = b.strOrNull('customer_name');
      final service = b.strOrNull('service');
      if (name == null || service == null) return _invalid();
      final amount = Money.tryFromJson(b['total_amount']) ?? Money.zero;
      if (amount.isNegative) return _invalid();
      final stage =
          ProjectStage.fromApi(b.strOrNull('stage')) ??
          ProjectStage.malzemeTemini;
      final p = <String, dynamic>{
        'id': db.nextId('prj'),
        'code': 'PRJ-${500 + db.projects.length + 1}',
        'offer_id': null,
        'customer_name': name,
        'customer_phone': null,
        'service': service,
        'stage': stage.api,
        'total_amount': tl(amount),
        'assigned_team': null,
        'start_date': DateTime.now().toUtc().toIso8601String(),
        'end_date': null,
        'notes': null,
        'owner_id': 'u-admin',
        'address': b.strOrNull('address'),
        'lat': null,
        'lng': null,
        'paid_amount': 0,
      };
      db.projects.insert(0, p);
      return DemoResponse.json(p, status: 201);
    }),
    DemoRoute('DELETE', '/projects/:id', (req) {
      if (req.role != UserRole.admin) return _forbidden();
      final p = projectOf(req.params['id']!);
      if (p == null) return DemoResponse.error(404, 'Proje bulunamadı.');
      final id = p['id'] as String;
      db.projects.remove(p);
      tasks.remove(id);
      extras.remove(id);
      db.payments.removeWhere((x) => x['project_id'] == id);
      db.expenses.removeWhere((x) => x['project_id'] == id);
      return DemoResponse.json({'message': 'Proje silindi.'});
    }),
    DemoRoute('GET', '/projects/:id/full', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final p = projectOf(req.params['id']!);
      if (p == null) return DemoResponse.error(404, 'Proje bulunamadı.');
      final id = p['id'] as String;
      return DemoResponse.json({
        'project': p,
        'tasks': tasks[id] ?? <JsonMap>[],
        'extras': extras[id] ?? <JsonMap>[],
        'payments': _isFinanceRole(req.role)
            ? db.payments.where((x) => x['project_id'] == id).toList()
            : <JsonMap>[],
        'expenses': _isFinanceRole(req.role)
            ? db.expenses.where((x) => x['project_id'] == id).toList()
            : <JsonMap>[],
      });
    }),
    DemoRoute('PATCH', '/projects/:id/stage', (req) {
      final p = projectOf(req.params['id']!);
      if (p == null) return DemoResponse.error(404, 'Proje bulunamadı.');
      final s = ProjectStage.fromApi(req.bodyMap.strOrNull('stage'));
      if (s == null) return _invalid();
      p['stage'] = s.api;
      if (s == ProjectStage.tamamlandi) {
        p['end_date'] = DateTime.now().toUtc().toIso8601String();
      }
      log('project', p['id'] as String, 'asama_degisti', s.api);
      return DemoResponse.json(p);
    }),
    DemoRoute('PATCH', '/projects/:id/amount', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final p = projectOf(req.params['id']!);
      if (p == null) return DemoResponse.error(404, 'Proje bulunamadı.');
      final m = Money.tryFromJson(req.bodyMap['total_amount']);
      if (m == null || m.isNegative) return _invalid();
      p['total_amount'] = tl(m);
      return DemoResponse.json(p);
    }),
    DemoRoute('PATCH', '/projects/:id/dates', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final p = projectOf(req.params['id']!);
      if (p == null) return DemoResponse.error(404, 'Proje bulunamadı.');
      final b = req.bodyMap;
      if (b.containsKey('start_date')) p['start_date'] = b['start_date'];
      if (b.containsKey('end_date')) p['end_date'] = b['end_date'];
      return DemoResponse.json(p);
    }),
    DemoRoute('PATCH', '/projects/:id', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final p = projectOf(req.params['id']!);
      if (p == null) return DemoResponse.error(404, 'Proje bulunamadı.');
      final b = req.bodyMap;
      for (final k in ['customer_name', 'service', 'notes', 'address']) {
        if (b.containsKey(k)) p[k] = b[k];
      }
      log('project', p['id'] as String, 'duzenlendi', null);
      return DemoResponse.json(p);
    }),
    DemoRoute('GET', '/projects/:id/collaborators', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      return DemoResponse.json([
        {'id': 'u-admin', 'name': 'Yönetici', 'role': 'admin'},
        {'id': 'u-personel', 'name': 'Personel', 'role': 'personel'},
        {'id': 'u-saha', 'name': 'Saha Ekibi', 'role': 'saha'},
      ]);
    }),

    // ---------------- Görevler ----------------
    DemoRoute('GET', '/projects/:id/tasks', (req) {
      final id = req.params['id']!;
      if (projectOf(id) == null) {
        return DemoResponse.error(404, 'Proje bulunamadı.');
      }
      return DemoResponse.json(tasks[id] ?? <JsonMap>[]);
    }),
    DemoRoute('POST', '/projects/:id/tasks', (req) {
      final id = req.params['id']!;
      if (projectOf(id) == null) {
        return DemoResponse.error(404, 'Proje bulunamadı.');
      }
      final title = req.bodyMap.strOrNull('title');
      if (title == null) {
        return DemoResponse.error(400, 'Başlık zorunludur.');
      }
      final t = <String, dynamic>{
        'id': db.nextId('tsk'),
        'project_id': id,
        'title': title,
        'status': 'bekliyor',
        'assigned_user_id': req.bodyMap.strOrNull('assigned_user_id'),
      };
      (tasks[id] ??= []).add(t);
      return DemoResponse.json(t, status: 201);
    }),
    DemoRoute('PATCH', '/projects/tasks/:taskId', (req) {
      for (final list in tasks.values) {
        final t = list
            .where((e) => e['id'] == req.params['taskId'])
            .firstOrNull;
        if (t != null) {
          final s = req.bodyMap.strOrNull('status');
          if (s != null) {
            if (TaskStatus.fromApi(s) == null) return _invalid();
            t['status'] = s;
          }
          final title = req.bodyMap.strOrNull('title');
          if (title != null) t['title'] = title;
          return DemoResponse.json(t);
        }
      }
      return DemoResponse.error(404, 'Görev bulunamadı.');
    }),
    DemoRoute('DELETE', '/projects/tasks/:taskId', (req) {
      for (final list in tasks.values) {
        final before = list.length;
        list.removeWhere((e) => e['id'] == req.params['taskId']);
        if (list.length != before) {
          return DemoResponse.json({'message': 'Görev silindi.'});
        }
      }
      return DemoResponse.error(404, 'Görev bulunamadı.');
    }),

    // ---------------- İlave işler ----------------
    DemoRoute('GET', '/projects/:id/extras', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      return DemoResponse.json(extras[req.params['id']!] ?? <JsonMap>[]);
    }),
    DemoRoute('POST', '/projects/:id/extras', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final id = req.params['id']!;
      if (projectOf(id) == null) {
        return DemoResponse.error(404, 'Proje bulunamadı.');
      }
      final d = req.bodyMap.strOrNull('description');
      final a = Money.tryFromJson(req.bodyMap['amount']);
      if (d == null || a == null) return _invalid();
      final e = <String, dynamic>{
        'id': db.nextId('ext'),
        'project_id': id,
        'description': d,
        'amount': tl(a),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      (extras[id] ??= []).insert(0, e);
      return DemoResponse.json(e, status: 201);
    }),
    DemoRoute('DELETE', '/projects/extras/:extraId', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      for (final list in extras.values) {
        final before = list.length;
        list.removeWhere((e) => e['id'] == req.params['extraId']);
        if (list.length != before) {
          return DemoResponse.json({'message': 'İlave iş silindi.'});
        }
      }
      return DemoResponse.error(404, 'Kayıt bulunamadı.');
    }),

    // ---------------- Belgeler ----------------
    DemoRoute('GET', '/documents/:type/:id', (req) {
      final key = '${req.params['type']}:${req.params['id']}';
      return DemoResponse.json(docs[key] ?? <JsonMap>[]);
    }),
    DemoRoute('POST', '/documents/:type/:id', (req) {
      final type = req.params['type']!;
      final id = req.params['id']!;
      var name = 'dosya.jpg';
      final body = req.body;
      if (body is FormData && body.files.isNotEmpty) {
        name = body.files.first.value.filename ?? name;
      }
      final ext = DocumentRules.extensionOf(name);
      if (!DocumentRules.allowedExtensions.contains(ext)) {
        return DemoResponse.error(400, 'Bu dosya türü yüklenemez.');
      }
      final d = <String, dynamic>{
        'id': db.nextId('doc'),
        'resource_type': type,
        'resource_id': id,
        'file_url':
            'https://api.controlx.com.tr/uploads/$name?exp=1795000000&sig=demo',
        'file_name': name,
        'uploaded_by': 'u-admin',
        'uploaded_by_name': 'Yönetici',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      (docs['$type:$id'] ??= []).insert(0, d);
      log(type, id, 'dosya_eklendi', name);
      return DemoResponse.json(d, status: 201);
    }),
    DemoRoute('DELETE', '/documents/:id', (req) {
      for (final list in docs.values) {
        final before = list.length;
        list.removeWhere((e) => e['id'] == req.params['id']);
        if (list.length != before) {
          return DemoResponse.json({'message': 'Belge silindi.'});
        }
      }
      return DemoResponse.error(404, 'Belge bulunamadı.');
    }),

    // ---------------- Paylaşım / aktivite / kullanıcılar ----------------
    DemoRoute('GET', '/shares/:type/:id', (req) {
      final key = '${req.params['type']}:${req.params['id']}';
      return DemoResponse.json(shares[key] ?? <JsonMap>[]);
    }),
    DemoRoute('POST', '/shares', (req) {
      if (req.role == UserRole.saha) return _forbidden();
      final b = req.bodyMap;
      final type = b.strOrNull('resource_type');
      final rid = b.strOrNull('resource_id');
      final uid = b.strOrNull('user_id');
      if (type == null || rid == null || uid == null) return _invalid();
      final list = shares['$type:$rid'] ??= [];
      if (list.any((e) => e['shared_with_user_id'] == uid)) {
        return DemoResponse.json({'message': 'Zaten paylaşılmış.'});
      }
      final names = {
        'u-personel': 'Personel',
        'u-saha': 'Saha Ekibi',
        'u-ortak': 'Ortak Firma',
      };
      final s = <String, dynamic>{
        'id': db.nextId('shr'),
        'resource_type': type,
        'resource_id': rid,
        'shared_with_user_id': uid,
        'shared_by_user_id': 'u-admin',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'user_name': names[uid] ?? 'Kullanıcı',
        'user_email': '$uid@demo.com',
      };
      list.add(s);
      log(type, rid, 'paylasildi', s['user_name'] as String);
      return DemoResponse.json(s, status: 201);
    }),
    DemoRoute('DELETE', '/shares/:id', (req) {
      for (final list in shares.values) {
        final before = list.length;
        list.removeWhere((e) => e['id'] == req.params['id']);
        if (list.length != before) {
          return DemoResponse.json({'message': 'Paylaşım kaldırıldı.'});
        }
      }
      return DemoResponse.error(404, 'Paylaşım bulunamadı.');
    }),
    DemoRoute('GET', '/activity/:type/:id', (req) {
      final key = '${req.params['type']}:${req.params['id']}';
      return DemoResponse.json(activity[key] ?? <JsonMap>[]);
    }),
    DemoRoute('GET', '/users', (req) {
      if (req.role != UserRole.admin && req.role != UserRole.ortak) {
        return _forbidden();
      }
      return DemoResponse.json([
        {
          'id': 'u-personel',
          'name': 'Personel',
          'email': 'personel@demo.com',
          'role': 'personel',
        },
        {
          'id': 'u-saha',
          'name': 'Saha Ekibi',
          'email': 'saha@demo.com',
          'role': 'saha',
        },
      ]);
    }),
    // Saha için proje listesi buradan gelir (§10: total_amount yok).
    DemoRoute('GET', '/dashboard-init', (req) {
      final saha = req.role == UserRole.saha;
      return DemoResponse.json({
        'offers': saha ? <JsonMap>[] : db.offers,
        'projects': db.projects.map((p) => projectRow(p, req.role)).toList(),
        'payments': <JsonMap>[],
        'appointments': <JsonMap>[],
        'expenses': <JsonMap>[],
        'customers': <JsonMap>[],
        'reminders': <JsonMap>[],
        'users': <JsonMap>[],
        'quoteTemplates': <JsonMap>[],
        'materials': <JsonMap>[],
        'recurringExpenses': <JsonMap>[],
        'financeSummary': null,
      });
    }),
  ];
}
