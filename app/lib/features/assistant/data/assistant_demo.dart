// DEMO (--dart-define=DEMO=true): asistan uçları. Sözleşme A1/A2/C örnek JSON'larıyla.
// Durum bellekte tutulur (kart onay/geri al, kapanış yanıtı, gelen kutusu okundu, öneri kararı).
import '../../../core/auth/auth_models.dart';
import '../../../core/demo/demo_db.dart';
import '../../../core/demo/demo_router.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/json.dart';

List<DemoRoute> assistantDemoRoutes(DemoDb db) {
  final state = _AssistantDemoState();
  bool finance(UserRole? r) =>
      r == UserRole.admin ||
      r == UserRole.muhasebe ||
      r == UserRole.ortak ||
      r == null;
  bool manager(UserRole? r) => finance(r);
  DemoResponse forbidden() =>
      DemoResponse.error(403, 'Bu işlem için yetkiniz yok.');

  const a = '/assistant';
  return [
    // ---------- Komut çubuğu ----------
    DemoRoute('POST', '$a/commands', (req) {
      final role = req.role;
      final text = req.bodyMap.strOr('text').toLowerCase();
      final choices = req.bodyMap.mapOrNull('choices') ?? const {};
      if (text.trim().isEmpty) {
        return DemoResponse.error(400, 'Komut metni boş olamaz.');
      }
      if (RegExp(r'(^|\s)sil(in|sene|sin)?(\s|$|[.!?])').hasMatch(text)) {
        return DemoResponse.json({
          'kind': 'answer',
          'intent': 'forbidden',
          'refused': true,
          'reason': 'delete',
          'text': 'Silme işlemlerini asistan yapmaz; ilgili ekrandan elle yapabilirsiniz.',
          'chips': ['Bugün ne var?'],
        });
      }
      if (text.contains('randevu')) {
        if (role == UserRole.saha) return forbidden();
        if (!choices.containsKey('customer_key')) {
          return DemoResponse.json({
            'kind': 'clarify',
            'intent': 'appointment.create',
            'reason': 'ambiguous_customer',
            'message': '"Ahmet" için birden fazla kayıt var. Hangisi?',
            'questions': [
              {
                'field': 'customer_key',
                'type': 'choice',
                'label': 'Müşteri',
                'options': [
                  {'value': '5321110000', 'label': 'Ahmet Yılmaz'},
                  {'value': '5321112222', 'label': 'Ahmet Kaya'},
                ],
              },
            ],
            'chips': ['Bugün ne var?'],
          });
        }
        final c = state.newCard(
          intent: 'appointment.create',
          summary:
              'Randevu: ${choices['customer_key'] == '5321112222' ? 'Ahmet Kaya' : 'Ahmet Yılmaz'} · Cumartesi 21 Kas 10:00 · Keşif',
          fields: [
            {
              'key': 'when',
              'label': 'Tarih ve saat',
              'type': 'datetime',
              'value': '2026-11-21T07:00:00.000Z',
              'display': '21 Kas 2026, 10:00',
              'editable': true,
            },
            {
              'key': 'type',
              'label': 'Tür',
              'type': 'choice',
              'value': 'Keşif',
              'display': 'Keşif',
              'editable': true,
              'options': [
                {'value': 'Keşif', 'label': 'Keşif'},
                {'value': 'Montaj', 'label': 'Montaj'},
              ],
            },
          ],
        );
        return DemoResponse.json({'kind': 'action_card', 'action': c});
      }
      if (text.contains('ödeme') || text.contains('odeme')) {
        if (!finance(role)) return forbidden();
        final c = state.newCard(
          intent: 'payment.add',
          summary: 'Ödeme: Ahmet Yılmaz · ₺5.000,00 · Nakit',
          fields: [
            {
              'key': 'amount',
              'label': 'Tutar',
              'type': 'money',
              'value': 5000,
              'display': '₺5.000,00',
              'editable': true,
            },
            {
              'key': 'method',
              'label': 'Yöntem',
              'type': 'text',
              'value': 'Nakit',
              'display': 'Nakit',
              'editable': false,
            },
          ],
          warnings: [
            'Bu müşterinin kalan bakiyesi ₺4.200,00; tutar bakiyeyi aşıyor.',
          ],
        );
        return DemoResponse.json({'kind': 'action_card', 'action': c});
      }
      if (text.contains('tahsilat')) {
        if (!finance(role)) return forbidden();
        return DemoResponse.json({
          'kind': 'answer',
          'intent': 'query.collections',
          'text': 'Kasım ayında şu ana kadar ₺92.000,00 tahsilat var.',
          'data': {
            'total_kurus': 9200000,
            'count': 7,
            'items': [
              {'name': 'Ahmet Yılmaz', 'amount_kurus': 5000000},
              {'name': 'Ege Evleri Site', 'amount_kurus': 4200000},
            ],
          },
          'chips': ['Geciken alacaklar'],
        });
      }
      if (text.contains('bugün') || text.contains('bugun')) {
        return DemoResponse.json({
          'kind': 'answer',
          'intent': 'query.agenda',
          'text': 'Bugün 3 randevunuz var. İlki 10:00 Ahmet Yılmaz (Keşif).',
          'data': {
            'count': 3,
            'items': [
              {'title': '10:00 Ahmet Yılmaz (Keşif)'},
              {'title': '13:30 Ege Evleri Site (Ölçü)'},
              {'title': '16:00 Marina Cafe (Montaj)'},
            ],
          },
          'chips': ['Bu ay ne kadar tahsilat?'],
        });
      }
      return DemoResponse.json({
        'kind': 'answer',
        'intent': 'unknown',
        'text': 'Bunu anlayamadım. Şunlardan birini mi demek istediniz?',
        'chips': [
          'Bugün ne var?',
          'Yarın 10\'da randevu ekle',
          if (finance(role)) 'Bu ay ne kadar tahsilat?',
        ],
      });
    }),
    DemoRoute(
      'GET',
      '$a/commands/chips',
      (req) => DemoResponse.json({
        'chips': ['Bugün ne var?', 'Yarın 10\'da randevu ekle'],
      }),
    ),
    DemoRoute('GET', '$a/actions/:id', (req) {
      final c = state.cards[req.params['id']];
      return c == null
          ? DemoResponse.error(404, 'Kart bulunamadı.')
          : DemoResponse.json(c);
    }),
    DemoRoute('PATCH', '$a/actions/:id', (req) {
      final c = state.cards[req.params['id']];
      if (c == null) return DemoResponse.error(404, 'Kart bulunamadı.');
      if (c['status'] != 'onerildi') {
        return DemoResponse.error(409, 'Bu kart artık düzenlenemez.');
      }
      final edits = req.bodyMap.mapOrNull('fields') ?? const {};
      for (final f in (c['fields'] as List).cast<Map<String, dynamic>>()) {
        if (edits.containsKey(f['key']) && f['editable'] == true) {
          f['value'] = edits[f['key']];
          f['display'] = '${edits[f['key']]}';
        }
      }
      return DemoResponse.json(c);
    }),
    DemoRoute('POST', '$a/actions/:id/confirm', (req) {
      final c = state.cards[req.params['id']];
      if (c == null) return DemoResponse.error(404, 'Kart bulunamadı.');
      if (c['status'] != 'onerildi') {
        return DemoResponse.error(409, 'Bu kart zaten işlendi.');
      }
      c['status'] = 'uygulandi';
      c['applied_at'] = Ist.now().toIso8601String();
      c['undo'] = {
        'available': true,
        'until': Ist.now().add(const Duration(minutes: 10)).toIso8601String(),
      };
      return DemoResponse.json(c);
    }),
    DemoRoute('POST', '$a/actions/:id/reject', (req) {
      final c = state.cards[req.params['id']];
      if (c == null) return DemoResponse.error(404, 'Kart bulunamadı.');
      if (c['status'] != 'onerildi') {
        return DemoResponse.error(409, 'Bu kart zaten işlendi.');
      }
      c['status'] = 'reddedildi';
      return DemoResponse.json(c);
    }),
    DemoRoute('POST', '$a/actions/:id/undo', (req) {
      final c = state.cards[req.params['id']];
      if (c == null) return DemoResponse.error(404, 'Kart bulunamadı.');
      if (c['status'] != 'uygulandi') {
        return DemoResponse.error(409, 'Geri alınamaz.');
      }
      c['status'] = 'geri_alindi';
      c['undo'] = {'available': false};
      return DemoResponse.json(c);
    }),

    // ---------- Brifing ----------
    DemoRoute('GET', '$a/briefing/today', (req) {
      final b = demoMorningBriefing(req.role ?? UserRole.admin);
      if (state.briefingRead) b['read_at'] = Ist.now().toIso8601String();
      return DemoResponse.json(b);
    }),
    DemoRoute('GET', '$a/briefings', (req) {
      final type = req.query['type'];
      final role = req.role ?? UserRole.admin;
      if ((type == 'weekly' || type == 'monthly') && !manager(role)) {
        return DemoResponse.json({'items': <Object?>[]});
      }
      final items = <Map<String, dynamic>>[
        demoMorningBriefing(role),
        if (manager(role)) demoWeeklyReport(),
        if (manager(role)) demoMonthlyReport(),
      ].where((b) => type == null || b['kind'] == type).toList();
      return DemoResponse.json(items);
    }),
    DemoRoute('POST', '$a/briefings/:id/read', (req) {
      state.briefingRead = true;
      return DemoResponse.json({
        'id': req.params['id'],
        'read_at': Ist.now().toIso8601String(),
      });
    }),

    // ---------- Müdür ----------
    DemoRoute('GET', '$a/insights', (req) {
      if (!manager(req.role)) return forbidden();
      final status = req.query['status'] ?? 'acik';
      final items = state.insights
          .where((i) => status == 'all' || i['status'] == status)
          .toList();
      return DemoResponse.json({'items': items, 'count': items.length});
    }),
    DemoRoute('POST', '$a/insights/:id/snooze', (req) {
      if (!manager(req.role)) return forbidden();
      return state.setInsight(req.params['id']!, 'ertelendi');
    }),
    DemoRoute('POST', '$a/insights/:id/dismiss', (req) {
      if (!manager(req.role)) return forbidden();
      return state.setInsight(req.params['id']!, 'kapatildi');
    }),
    DemoRoute('POST', '$a/insights/:id/applied', (req) {
      if (!manager(req.role)) return forbidden();
      return state.setInsight(req.params['id']!, 'uygulandi');
    }),
    DemoRoute('POST', '$a/insights/:id/feedback', (req) {
      if (!manager(req.role)) return forbidden();
      final v = req.bodyMap.strOr('verdict');
      if (!const {'yanlis', 'alakasiz', 'yararli'}.contains(v)) {
        return DemoResponse.error(400, 'Geçersiz değer.');
      }
      return v == 'yararli'
          ? DemoResponse.json({'ok': true})
          : state.setInsight(req.params['id']!, 'kapatildi');
    }),
    DemoRoute('GET', '$a/insight-rules', (req) {
      if (req.role != UserRole.admin && req.role != null) return forbidden();
      return DemoResponse.json(state.rulesJson());
    }),
    DemoRoute('PUT', '$a/insight-rules', (req) {
      if (req.role != UserRole.admin && req.role != null) return forbidden();
      for (final r in req.bodyMap.list('rules')) {
        for (final rule in state.rules) {
          if (rule['rule_key'] == r['rule_key']) {
            if (r.containsKey('enabled')) {
              rule['enabled'] = r['enabled'];
              rule['status'] = r['enabled'] == true ? 'aktif' : 'kapali';
            }
            final p = r.mapOrNull('params');
            if (p != null) {
              (rule['params'] as Map<String, dynamic>).addAll(p);
            }
          }
        }
      }
      return DemoResponse.json(state.rulesJson());
    }),

    // ---------- Kapanış ----------
    DemoRoute('GET', '$a/closure/today', (req) {
      return DemoResponse.json(state.closure(req.role ?? UserRole.admin));
    }),
    DemoRoute('POST', '$a/closure/answers', (req) {
      final role = req.role ?? UserRole.admin;
      final answers = req.bodyMap.list('answers');
      for (final an in answers) {
        if (an.containsKey('choice') && an['choice'] == null) {
          return DemoResponse.error(400, 'Geçersiz yanıt.');
        }
        if (an['question_id'] == 'money' &&
            an['choice'] == 'tahsilat' &&
            (an['amount_kurus'] is! int || (an['amount_kurus'] as int) <= 0)) {
          return DemoResponse.error(400, 'Tutar pozitif tam sayı olmalı.');
        }
      }
      state.closureAnswers = answers;
      state.closureNote = req.bodyMap.strOrNull('free_note');
      if (req.bodyMap.boolOr('finish')) state.closureDone = true;
      final log = state.closure(role);
      return DemoResponse.json({
        'applied': [
          for (final an in answers)
            if (an['skipped'] != true)
              {'question_id': an['question_id'], 'type': 'recorded'},
        ],
        'closure_proposals': log['closure_proposals'],
        'log': log,
        'summary_card': log['summary_card'],
      });
    }),

    // ---------- Gelen kutusu / tercihler ----------
    DemoRoute('GET', '$a/inbox', (req) {
      var items = state.inbox;
      if (req.query['unread'] == '1') {
        items = items.where((i) => i['read_at'] == null).toList();
      }
      final limit = int.tryParse(req.query['limit'] ?? '') ?? 30;
      final unread = state.inbox.where((i) => i['read_at'] == null).length;
      return DemoResponse.json({
        'items': items.take(limit).toList(),
        'unread_count': unread,
        'next_before': null,
      });
    }),
    DemoRoute('POST', '$a/inbox/read-all', (req) {
      var n = 0;
      for (final i in state.inbox) {
        if (i['read_at'] == null) {
          i['read_at'] = Ist.now().toIso8601String();
          n++;
        }
      }
      return DemoResponse.json({'marked': n});
    }),
    DemoRoute('POST', '$a/inbox/:id/read', (req) {
      for (final i in state.inbox) {
        if (i['id'] == req.params['id']) {
          i['read_at'] ??= Ist.now().toIso8601String();
          return DemoResponse.json(i);
        }
      }
      return DemoResponse.error(404, 'Bildirim bulunamadı.');
    }),
    DemoRoute('POST', '$a/inbox/:id/ack', (req) {
      for (final i in state.inbox) {
        if (i['id'] == req.params['id']) {
          i['read_at'] ??= Ist.now().toIso8601String();
          i['acked_at'] = Ist.now().toIso8601String();
          return DemoResponse.json(i);
        }
      }
      return DemoResponse.error(404, 'Bildirim bulunamadı.');
    }),
    DemoRoute('GET', '$a/prefs', (req) => DemoResponse.json(state.prefs)),
    DemoRoute('PUT', '$a/prefs', (req) {
      final b = req.bodyMap;
      for (final t in const [
        'morning_time',
        'evening_time',
        'quiet_start',
        'quiet_end',
      ]) {
        final v = b[t];
        if (v is String && !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v)) {
          return DemoResponse.error(400, 'Geçersiz saat.');
        }
      }
      state.prefs.addAll(b);
      state.prefs['is_default'] = false;
      return DemoResponse.json(state.prefs);
    }),

    // ---------- Yazışma içe aktarma ----------
    DemoRoute('GET', '$a/imports/consent-notice', (req) {
      if (req.role == UserRole.saha) return forbidden();
      return DemoResponse.json({
        'version': '2026-11-v1',
        'title': 'Yazışmanın işlenmesi hakkında aydınlatma',
        'text': [
          'Paylaştığınız yazışma yalnız bu sunucuda işlenir; üçüncü taraflara gönderilmez.',
          'Yapay zekâ kullanılmaz; notlar ve öneriler kurallarla çıkarılır.',
          'Verileri istediğiniz zaman müşteri kartından silebilirsiniz.',
        ],
        'checkbox':
            'Okudum; müşterimin yazışmasının işlenmesine onay veriyorum.',
      });
    }),
    DemoRoute('POST', '$a/imports', (req) {
      if (req.role == UserRole.saha) return forbidden();
      final b = req.bodyMap;
      if (b['consent'] == null || b['consent'] == false) {
        return DemoResponse.error(400, 'Rıza onayı gerekli.');
      }
      return DemoResponse.json(state.importPreview(), status: 201);
    }),
    DemoRoute('POST', '$a/imports/:id/confirm', (req) {
      if (state.imported) {
        return DemoResponse.json({
          'already': true,
          'conversation_id': 'conv-1',
        });
      }
      final b = req.bodyMap;
      if (b.strOr('owner_sender').isEmpty) {
        return DemoResponse.error(400, 'Sohbetin sahibi seçilmeli.');
      }
      state.imported = true;
      return DemoResponse.json({
        'already': false,
        'conversation_id': 'conv-1',
        'inserted': 143,
        'duplicates': 0,
        'suggestions_created': state.suggestions.length,
      }, status: 201);
    }),
    DemoRoute(
      'DELETE',
      '$a/imports/:id',
      (req) => DemoResponse.json({'message': 'Silindi.'}),
    ),
    DemoRoute('GET', '$a/suggestions', (req) {
      final status = req.query['status'] ?? 'beklemede';
      return DemoResponse.json(
        state.suggestions
            .where((s) => status == 'all' || s['status'] == status)
            .toList(),
      );
    }),
    DemoRoute('PATCH', '$a/suggestions/:id', (req) {
      for (final s in state.suggestions) {
        if (s['id'] == req.params['id']) {
          final to = req.bodyMap.strOr('status');
          if (s['status'] == to)
            return DemoResponse.json({...s, 'replayed': true});
          if (s['status'] != 'beklemede') {
            return DemoResponse.error(
              409,
              'Bu öneri için başka bir karar verilmiş.',
            );
          }
          s['status'] = to;
          final f = req.bodyMap.mapOrNull('fields');
          if (f != null) (s['fields'] as Map<String, dynamic>).addAll(f);
          if (to == 'kabul' && s['kind'] == 'randevu') {
            final c = state.newCard(
              intent: 'appointment.create',
              summary: 'Randevu: Ahmet Yılmaz · Cuma 27 Kas 10:00 · Keşif',
              fields: const [],
            );
            return DemoResponse.json({'suggestion': s, 'action': c});
          }
          return DemoResponse.json({'suggestion': s});
        }
      }
      return DemoResponse.error(404, 'Öneri bulunamadı.');
    }),
    DemoRoute('GET', '$a/conversations', (req) {
      return DemoResponse.json(
        state.imported
            ? [
                {
                  'id': 'conv-1',
                  'title': 'Ahmet Yılmaz',
                  'message_count': 143,
                  'last_message_at': '2026-11-20T08:12:00.000Z',
                  'first_message_at': '2026-11-12T10:00:00.000Z',
                },
              ]
            : <Object?>[],
      );
    }),
    DemoRoute('DELETE', '$a/conversations/:id', (req) {
      state.imported = false;
      return DemoResponse.json({'message': 'Silindi.'});
    }),
    DemoRoute(
      'GET',
      '$a/customers/:key/notes',
      (req) => DemoResponse.json([
        {
          'id': 'n1',
          'text': 'Cuma günü balkon ölçüsü 3,2 m olacak.',
          'author': 'rule',
          'tags': ['ölçü'],
          'created_at': '2026-11-19T09:00:00.000Z',
        },
      ]),
    ),
    DemoRoute('DELETE', '$a/customers/:key/data', (req) {
      state.imported = false;
      return DemoResponse.json({'message': 'Silindi.'});
    }),
    DemoRoute(
      'GET',
      '$a/consents',
      (req) => DemoResponse.json([
        {
          'id': 'c1',
          'type': 'aydinlatma',
          'version': '2026-11-v1',
          'created_at': '2026-11-20T08:00:00.000Z',
        },
      ]),
    ),
    DemoRoute(
      'POST',
      '$a/consents/:id/withdraw',
      (req) => DemoResponse.json({
        'id': req.params['id'],
        'withdrawn_at': Ist.now().toIso8601String(),
      }),
    ),
  ];
}

class _AssistantDemoState {
  final Map<String, Map<String, dynamic>> cards = {};
  int _seq = 0;
  bool briefingRead = false;
  bool closureDone = false;
  List<JsonMap> closureAnswers = const [];
  String? closureNote;
  bool imported = false;

  Map<String, dynamic> newCard({
    required String intent,
    required String summary,
    required List<Map<String, dynamic>> fields,
    List<String> warnings = const [],
  }) {
    final id = 'card-${++_seq}';
    final c = <String, dynamic>{
      'id': id,
      'origin': 'command_bar',
      'intent': intent,
      'risk': 'orta',
      'status': 'onerildi',
      'text': summary,
      'summary': summary,
      'fields': fields,
      'ambiguities': <Object?>[],
      'warnings': warnings,
      'undo': {'available': false},
      'created_at': Ist.now().toIso8601String(),
      'expires_at': Ist.now().add(const Duration(hours: 24)).toIso8601String(),
    };
    cards[id] = c;
    return c;
  }

  final List<Map<String, dynamic>> insights = [
    {
      'id': 'ins-1',
      'rule_key': 'M2',
      'rule_title': 'Tahsilat gecikmesi',
      'severity': 'warn',
      'status': 'acik',
      'title': 'Ahmet Kaya: ₺12.450,55 tahsilat bekliyor, 10 gündür açık',
      'body': 'Ahmet Kaya için iş \'Teslim\' aşamasına geçeli 10 gün oldu; kalan bakiye ₺12.450,55. Nazik bir hatırlatma göndermek ya da aramak iyi olabilir.',
      'entity': {'type': 'project', 'id': 'p-1'},
      'evidence': {
        'rule': 'M2',
        'why': 'Teslim sonrası 7 günü aşan açık bakiye.',
        'metrics': [
          {
            'key': 'balance',
            'label': 'Kalan bakiye',
            'value': 1245055,
            'unit': 'kurus',
            'display': '₺12.450,55',
          },
          {
            'key': 'age',
            'label': 'Aşamaya geçeli gün',
            'value': 10,
            'unit': 'days',
            'display': '10 gün',
          },
        ],
        'refs': [
          {'type': 'project', 'id': 'p-1', 'label': 'PRJ-T1 · Ahmet Kaya'},
        ],
      },
      'actions': [
        {
          'type': 'whatsapp.template',
          'label': 'Hatırlatma taslağı',
          'template_code': 'odeme_hatirlatma',
          'phone': '05321234567',
          'text': 'Merhaba Ahmet Bey, ₺12.450,55 tutarındaki bakiye için hatırlatma yapmak istedik.',
          'url': 'https://wa.me/905321234567?text=Merhaba',
        },
        {
          'type': 'call',
          'label': 'Ara: Ahmet',
          'phone': '05321234567',
          'tel_uri': 'tel:+905321234567',
        },
        {
          'type': 'reminder.create',
          'label': 'Hatırlat',
          'endpoint': {'method': 'POST', 'path': '/api/reminders'},
          'body': {
            'title': 'Tahsilat: Ahmet Kaya',
            'remind_at': '2026-11-26T06:00:00.000Z',
            'project_id': 'p-1',
            'note': 'Müdür önerisinden',
          },
        },
        {'type': 'open', 'label': 'Aç', 'entity_type': 'project', 'id': 'p-1'},
        {'type': 'zaman_makinesi', 'label': 'Bilinmeyen'},
      ],
    },
    {
      'id': 'ins-2',
      'rule_key': 'M4',
      'rule_title': 'Boş takvim',
      'severity': 'info',
      'status': 'acik',
      'title': 'Önümüzdeki 7 günün 4\'ü boş; 6 teklif yanıt bekliyor',
      'body': 'Bugün 3 teklifi aramak 2 keşif doldurabilir.',
      'entity': {'type': 'offer', 'id': 'o-1'},
      'evidence': {
        'metrics': [
          {
            'key': 'empty',
            'label': 'Boş gün',
            'value': 4,
            'unit': 'count',
            'display': '4',
          },
        ],
      },
      'actions': [
        {
          'type': 'appointment.create',
          'label': 'Randevu ekle',
          'body': {'type': 'Keşif'},
          'suggested_dates': ['2026-11-23'],
        },
      ],
    },
  ];

  DemoResponse setInsight(String id, String status) {
    for (final i in insights) {
      if (i['id'] == id) {
        i['status'] = status;
        return DemoResponse.json(i);
      }
    }
    return DemoResponse.error(404, 'Öneri bulunamadı.');
  }

  final List<Map<String, dynamic>> rules = [
    {
      'rule_key': 'M2',
      'title': 'Tahsilat gecikmesi',
      'description': 'Teslim sonrası açık bakiye.',
      'group': 'Para',
      'enabled': true,
      'status': 'aktif',
      'params': {'warn_days': 7, 'critical_days': 21},
      'defaults': {'warn_days': 7, 'critical_days': 21},
    },
    {
      'rule_key': 'M4',
      'title': 'Boş takvim',
      'description': 'Önümüzdeki 7 iş gününde boş gün.',
      'group': 'Satış',
      'enabled': false,
      'status': 'kapali',
      'params': {'warn_days': 3},
      'defaults': {'warn_days': 3},
    },
    {
      'rule_key': 'M7',
      'title': 'Faturasız tahsilat',
      'description': 'Bağımlı kural.',
      'group': 'Vergi',
      'enabled': true,
      'status': 'bagimli',
      'dependency': {
        'requires': ['invoices'],
        'available': false,
        'missing': ['invoices'],
      },
      'params': <String, dynamic>{},
      'defaults': <String, dynamic>{},
    },
  ];

  Map<String, dynamic> rulesJson() => {
    'calibration_mode': false,
    'rules': rules,
  };

  final List<Map<String, dynamic>> inbox = [
    {
      'id': 'in-1',
      'type': 'briefing',
      'title': 'Günaydın: 3 randevu, 1 geciken tahsilat',
      'body': 'İlk randevu 10:00 Ahmet Yılmaz.',
      'data': {'kind': 'morning', 'date': '2026-11-20'},
      'priority': 'normal',
      'status': 'gonderildi',
      'created_at': '2026-11-20T04:30:00.000Z',
      'read_at': null,
    },
    {
      'id': 'in-2',
      'type': 'offer',
      'title': 'Yeni teklif talebi',
      'body': 'Can Öz — Mutfak',
      'data': {'type': 'offer', 'id': 'o-77'},
      'status': 'gonderildi',
      'created_at': '2026-11-19T12:00:00.000Z',
      'read_at': null,
    },
    {
      'id': 'in-3',
      'type': 'closure',
      'title': 'Gün kapanıyor',
      'body': '4 kısa soru var.',
      'data': {'kind': 'evening', 'questions': 4},
      'status': 'gonderildi',
      'created_at': '2026-11-19T15:30:00.000Z',
      'read_at': '2026-11-19T16:00:00.000Z',
    },
  ];

  final Map<String, dynamic> prefs = {
    'enabled': true,
    'tz': 'Europe/Istanbul',
    'morning_enabled': true,
    'evening_enabled': true,
    'morning_time': '07:30',
    'evening_time': '18:30',
    'quiet_enabled': true,
    'quiet_start': '21:30',
    'quiet_end': '07:00',
    'weekdays': [1, 2, 3, 4, 5, 6],
    'channels': {'push': true, 'inbox': true},
    'categories': <String, dynamic>{},
    'max_proactive_per_day': 5,
    'critical_in_quiet': false,
    'is_default': true,
  };

  final List<Map<String, dynamic>> suggestions = [
    {
      'id': 'sg-1',
      'kind': 'not',
      'status': 'beklemede',
      'text': 'Balkon ölçüsü 3,2 m olacak (Cuma).',
      'fields': {'text': 'Balkon ölçüsü 3,2 m olacak (Cuma).'},
      'conversation_id': 'conv-1',
      'message_ref': 'msg_12',
      'source': {
        'id': 'msg_12',
        'sender': 'Ahmet Yılmaz',
        'text': 'Cuma günü balkon ölçüsü 3,2 m olacak, haberiniz olsun.',
        'sent_at': '2026-11-19T08:55:00.000Z',
      },
    },
    {
      'id': 'sg-2',
      'kind': 'hatirlatma',
      'status': 'beklemede',
      'text': 'Ahmet Yılmaz\'ı yarın ara.',
      'fields': {
        'title': 'Ahmet Yılmaz\'ı ara',
        'remind_at': '2026-11-21T06:00:00.000Z',
      },
      'conversation_id': 'conv-1',
      'message_ref': 'msg_30',
      'source': {
        'id': 'msg_30',
        'sender': 'Ahmet Yılmaz',
        'text': 'Yarın sabah beni arar mısınız?',
        'sent_at': '2026-11-19T20:10:00.000Z',
      },
    },
    {
      'id': 'sg-3',
      'kind': 'randevu',
      'status': 'beklemede',
      'text': 'Cuma 10:00 keşif randevusu.',
      'fields': {'when': '2026-11-27T07:00:00.000Z', 'type': 'Keşif'},
      'conversation_id': 'conv-1',
      'message_ref': 'msg_41',
      'source': {
        'id': 'msg_41',
        'sender': 'Ahmet Yılmaz',
        'text': 'Cuma 10:00 uygun mu?',
        'sent_at': '2026-11-19T21:00:00.000Z',
      },
    },
  ];

  Map<String, dynamic> importPreview() => {
    'id': 'imp-1',
    'status': 'onizleme',
    'file': {'name': 'WhatsApp Chat with Ahmet Yılmaz.txt'},
    'stats': {'messages': 143, 'participants': 2},
    'participants': ['Ahmet Yılmaz', 'Siz'],
    'is_group': false,
    'suggested_owner_sender': 'Siz',
    'candidates': [
      {
        'customer_key': '5321110000',
        'name': 'Ahmet Yılmaz',
        'phone': '05321110000',
      },
    ],
    'customer': {
      'customer_key': '5321110000',
      'name': 'Ahmet Yılmaz',
      'phone': '05321110000',
    },
    'already_imported': false,
    'single_message': false,
    'warnings': <Object?>[],
    'preview_messages': {
      'first': {
        'sender': 'Ahmet Yılmaz',
        'text': 'Merhaba, keşif için müsait misiniz?',
        'sent_at': '2026-11-12T07:00:00.000Z',
      },
      'last': {
        'sender': 'Siz',
        'text': 'Tamamdır, Cuma görüşürüz.',
        'sent_at': '2026-11-20T05:12:00.000Z',
      },
    },
    'suggestion_counts': {'not': 1, 'hatirlatma': 1, 'randevu': 1},
    'expires_at': '2026-11-21T08:00:00.000Z',
  };

  Map<String, dynamic> closure(UserRole role) {
    final isField = role == UserRole.saha;
    final hasMoney = !isField;
    final answered = {for (final a in closureAnswers) a['question_id']: a};
    final qs = <Map<String, dynamic>>[
      {
        'id': 'appt:a1',
        'kind': 'appointment',
        'text': '10:00 Ahmet Yılmaz (Keşif): nasıl geçti?',
        'skippable': true,
        'context': {'appointment_id': 'a1', 'customer_name': 'Ahmet Yılmaz'},
        'options': [
          {
            'value': 'yapildi',
            'label': 'Yapıldı',
            'follow_up': [
              {'value': 'teklif_verilecek', 'label': 'Teklif verilecek'},
              {'value': 'anlastik', 'label': 'Anlaştık'},
              {'value': 'dusunecek', 'label': 'Düşünecek'},
              {'value': 'sonra_ara', 'label': 'Sonra ara'},
            ],
          },
          {'value': 'ertelendi', 'label': 'Ertelendi'},
          {'value': 'iptal', 'label': 'İptal'},
        ],
        'answer': answered['appt:a1'],
      },
      if (hasMoney)
        {
          'id': 'money',
          'kind': 'money',
          'text': 'Bugün tahsilat ya da gider oldu mu?',
          'skippable': true,
          'context': {'payments_count': 0},
          'options': [
            {'value': 'yok', 'label': 'Yok'},
            {'value': 'tahsilat', 'label': '+ Tahsilat'},
            {'value': 'gider', 'label': '+ Gider'},
          ],
          'answer': answered['money'],
        },
      {
        'id': 'tomorrow',
        'kind': 'tomorrow',
        'text': 'Yarın 1 randevu var. Hazır mıyız?',
        'skippable': true,
        'context': {'count': 1},
        'options': [
          {'value': 'tamam', 'label': 'Tamam'},
          {'value': 'hatirlat', 'label': '+ Hatırlat'},
        ],
        'answer': answered['tomorrow'],
      },
    ];
    final moneyAnswer = answered['money'];
    final proposals = <Map<String, dynamic>>[
      if (hasMoney &&
          moneyAnswer != null &&
          moneyAnswer['choice'] == 'tahsilat')
        {
          'type': 'payment_create',
          'question_id': 'money',
          'label': 'Tahsilat ekle',
          'amount_kurus': moneyAnswer['amount_kurus'],
          'project_id': 'p-1',
          'apply': {
            'method': 'POST',
            'path': '/api/projects/p-1/payments',
            'body': {'amount': 1500, 'method': 'Nakit'},
            'needs': <String>[],
          },
        },
    ];
    return {
      'date': '2026-11-20',
      'status': closureDone
          ? 'done'
          : (answered.isEmpty ? 'pending' : 'partial'),
      'completeness': closureDone ? 100 : 0,
      'closed_at': closureDone ? Ist.now().toIso8601String() : null,
      'questions': qs,
      'free_note': closureNote,
      'note_prompt': 'Not düşmek istediğiniz bir şey var mı?',
      'skip_label': 'Atla',
      'summary_card': {
        'title': 'Gün sonu özeti',
        'date': '2026-11-20',
        'date_text': '20 Kas 2026',
        'appointments': {
          'total': 3,
          'done': answered.isEmpty ? 0 : 1,
          'postponed': 0,
          'cancelled': 0,
          'open': 2,
        },
        if (hasMoney) 'money': {'collected_kurus': 0, 'expense_kurus': 0},
        'new_requests_today': 0,
        'followups_created': 0,
        'tomorrow': {'count': 1, 'first': '10:00 Ahmet Yılmaz (Montaj)'},
        'completion': {
          'total': qs.length,
          'answered': answered.length,
          'skipped': 0,
          'percent': 0,
        },
        'text': '3 randevu: 1 yapıldı, 2 sonuçsuz. Yarın: 1 randevu (ilk: 10:00 Ahmet Yılmaz (Montaj)).',
      },
      'closure_proposals': proposals,
    };
  }
}

/// Sözleşme A2 §1 örneğine göre sabah brifingi; rol süzgeci sunucudaki gibi uygulanır.
Map<String, dynamic> demoMorningBriefing(UserRole role) {
  final isField = role == UserRole.saha;
  final isPersonel = role == UserRole.personel;
  final money = !isField && !isPersonel;
  final blocks = <Map<String, dynamic>>[
    {
      'id': 'appointments',
      'type': 'appointments',
      'title': 'Bugünün randevuları',
      'count': 2,
      'items': [
        {
          'id': 'a1',
          'time': '10:00',
          'scheduled_at': '2026-11-20T07:00:00.000Z',
          'type': 'Keşif',
          'status': 'beklemede',
          'customer_name': 'Ahmet Yılmaz',
          'customer_phone': '05321234567',
          'service': 'Mutfak',
          'address': 'Bodrum Merkez',
          'summary': '10:00 Ahmet Yılmaz (Keşif, Bodrum Merkez)',
          'actions': {
            'call': 'tel:+905321234567',
            'whatsapp': 'https://wa.me/905321234567',
            'directions': 'geo:0,0?q=Bodrum%20Merkez',
          },
        },
        {
          'id': 'a2',
          'time': '13:30',
          'scheduled_at': '2026-11-20T10:30:00.000Z',
          'type': 'Ölçü',
          'status': 'beklemede',
          'customer_name': 'Ege Evleri Site',
          'customer_phone': '05339876543',
          'summary': '13:30 Ege Evleri Site (Ölçü)',
          'actions': {
            'call': 'tel:+905339876543',
            'whatsapp': 'https://wa.me/905339876543',
            'directions': null,
          },
        },
      ],
    },
    {
      'id': 'reminders',
      'type': 'reminders',
      'title': 'Hatırlatma ve takipler',
      'count': 2,
      'reminders': [
        {'id': 'r1', 'title': 'Ara', 'time': '10:30', 'overdue': false},
      ],
      'followups': <Object?>[],
      'quote_waiting': [
        {'customer_name': 'Ayşe Demir', 'age_days': 8},
      ],
    },
    if (money)
      {
        'id': 'attention',
        'type': 'attention',
        'title': 'Dikkat',
        'count': 1,
        'items': [
          {
            'kind': 'insight',
            'insight_id': 'ins-1',
            'rule_key': 'M2b',
            'severity': 'critical',
            'title': 'Son 90 günde tahsilat oranı %39,8',
            'text': 'Sözleşme toplamı ₺29.000,55; tahsil edilen ₺11.550,00 (%39,8).',
            'actions': [
              {
                'type': 'screen',
                'label': 'Göster',
                'screen': 'receivables',
                'params': <String, dynamic>{},
              },
            ],
          },
        ],
      },
    if (!isField)
      {
        'id': 'new_requests',
        'type': 'new_requests',
        'title': 'Yeni teklifler',
        'count': 2,
        'oldest_age_hours': 49,
        'items': [
          {
            'customer_name': 'Can Öz',
            'summary': 'Can Öz — Mutfak',
            'actions': {
              'call': 'tel:+905320000001',
              'whatsapp': 'https://wa.me/905320000001',
              'directions': null,
            },
          },
        ],
      },
    {
      'id': 'overdue_jobs',
      'type': 'overdue_jobs',
      'title': 'Geciken işler',
      'count': 1,
      'items': [
        {
          'id': 'p2',
          'code': 'PRJ-T3',
          'customer_name': 'Su Yıldız',
          'days_overdue': 8,
        },
      ],
    },
    if (money)
      {
        'id': 'collections',
        'type': 'collections',
        'title': 'Geciken tahsilatlar',
        'count': 1,
        'total_kurus': 1245055,
        'total_text': '₺12.450,55',
        'items': [
          {
            'project_id': 'p-1',
            'customer_name': 'Ahmet Kaya',
            'balance_kurus': 1245055,
            'balance_text': '₺12.450,55',
            'age_days': 10,
            'actions': {
              'call': 'tel:+905321234567',
              'whatsapp': 'https://wa.me/905321234567',
              'directions': null,
            },
          },
        ],
      },
    if (!isField)
      {
        'id': 'low_stock',
        'type': 'low_stock',
        'title': 'Düşük stok',
        'count': 1,
        'items': [
          {
            'id': 'm1',
            'name': 'Silikon',
            'unit': 'adet',
            'stock': 2,
            'threshold': 5,
          },
        ],
      },
    if (money)
      {
        'id': 'money',
        'type': 'money',
        'title': 'Para özeti',
        'text': 'Dün tahsilat ₺2.000,00, gider ₺0,00; bu ay net -₺7.450,50.',
        'yesterday': {'collected_kurus': 200000, 'expense_kurus': 0},
        'month': {
          'collected_kurus': 755000,
          'expense_kurus': 1500050,
          'net_kurus': -745050,
        },
      },
    if (money)
      {
        'id': 'question',
        'type': 'question',
        'title': 'Tek soru',
        'kind': 'set_end_date',
        'project_id': 'p-2',
        'text': 'Kapı Müşteri 4 iş: teslim tarihi boş. Girelim mi?',
        'chips': [
          {'label': 'Bugün', 'value': '2026-11-20'},
          {'label': 'Bu hafta', 'value': '2026-11-27'},
          {'label': 'Sonra', 'value': null},
        ],
        'apply': {
          'method': 'PATCH',
          'path': '/api/projects/<id>/dates',
          'body_field': 'end_date',
        },
      },
    {
      'id': 'missed_closure',
      'type': 'missed_closure',
      'title': 'Dünün kapanışı',
      'date': '2026-11-19',
      'unresolved': 2,
      'text': 'Dün kapanış yapılmadı; 2 randevu sonucu belirsiz.',
      'action': {'screen': 'closure', 'date': '2026-11-19'},
    },
  ];
  final title = isField
      ? 'Günaydın: 2 randevu'
      : 'Günaydın: 2 randevu, 1 geciken tahsilat, 1 takip';
  return {
    'id': 'br-morning',
    'kind': 'morning',
    'date': '2026-11-20',
    'title': title,
    'text': 'Cuma, 20 Kas 2026\nRandevular: 10:00 Ahmet Yılmaz (Keşif); 13:30 Ege Evleri Site (Ölçü).',
    'data': {
      'v': 1,
      'kind': 'morning',
      'date': '2026-11-20',
      'weekday': 'Cuma',
      'date_text': '20 Kas 2026',
      'greeting': 'Günaydın',
      'role': role.api,
      'empty': false,
      'day_kind': null,
      'holiday': null,
      'stats': {
        'appointments': 2,
        'reminders': 1,
        'followups': 1,
        'new_requests': isField ? 0 : 2,
        'overdue_jobs': 1,
        'late_collections': money ? 1 : 0,
        'low_stock': isField ? 0 : 1,
        'attention': money ? 1 : 0,
        'tomorrow_appointments': 1,
      },
      'blocks': blocks,
    },
    'generated_by': 'job',
    'generated_at': '2026-11-20T04:30:01.000Z',
    'read_at': null,
    'live': false,
  };
}

Map<String, dynamic> demoWeeklyReport() => {
  'id': 'br-weekly',
  'kind': 'weekly',
  'date': '2026-11-16',
  'title': 'Haftalık rapor: net ₺12.300,00',
  'text': 'Geçen hafta tahsilat ₺32.000,00, gider ₺19.700,00.',
  'data': {
    'v': 1,
    'kind': 'weekly',
    'period': {
      'from': '2026-11-09',
      'to': '2026-11-15',
      'label': '9-15 Kas 2026',
    },
    'money': {
      'collected_kurus': 3200000,
      'expense_kurus': 1970000,
      'net_kurus': 1230000,
      'prev_net_kurus': 800000,
      'net_change_kurus': 430000,
      'note': 'Kişisel giderler net hesabına girmez.',
    },
    'offers': {
      'new': 5,
      'quoted': 3,
      'accepted': 1,
      'rejected': 1,
      'conversion_recent_bp': 3100,
    },
    'late_collections': {
      'count': 2,
      'total_kurus': 3640055,
      'items': <Object?>[],
    },
    'top_actions': [
      {
        'insight_id': 'ins-1',
        'rule_key': 'M2',
        'severity': 'warn',
        'title': 'Ahmet Kaya: ₺12.450,55 tahsilat bekliyor',
        'text': '10 gündür açık bakiye.',
        'why': [
          {
            'key': 'balance',
            'label': 'Kalan bakiye',
            'value': 1245055,
            'unit': 'kurus',
            'display': '₺12.450,55',
          },
        ],
        'actions': <Object?>[],
      },
      {
        'insight_id': 'ins-2',
        'rule_key': 'M4',
        'severity': 'info',
        'title': 'Önümüzdeki hafta 4 gün boş',
        'text': '6 teklif yanıt bekliyor.',
        'why': <Object?>[],
        'actions': <Object?>[],
      },
    ],
  },
  'generated_by': 'job',
  'generated_at': '2026-11-16T04:40:00.000Z',
  'read_at': null,
};

Map<String, dynamic> demoMonthlyReport() => {
  'id': 'br-monthly',
  'kind': 'monthly',
  'date': '2026-10-01',
  'title': 'Ekim raporu: net ₺41.200,00',
  'text': 'Tahsilat ₺120.000,00, gider ₺78.800,00.',
  'data': {
    'v': 1,
    'kind': 'monthly',
    'period': {'month': '2026-10', 'label': 'Ekim 2026'},
    'money': {
      'collected_kurus': 12000000,
      'expense_kurus': 7880000,
      'net_kurus': 4120000,
      'prev_net_kurus': 3500000,
      'net_change_kurus': 620000,
    },
    'offers': {
      'new': 20,
      'quoted': 12,
      'accepted': 5,
      'rejected': 4,
      'conversion_recent_bp': 2500,
    },
    'receivables': {'total_kurus': 5000000},
    'top_actions': <Object?>[],
  },
  'generated_by': 'job',
  'generated_at': '2026-11-01T04:40:00.000Z',
  'read_at': '2026-11-01T06:00:00.000Z',
};
