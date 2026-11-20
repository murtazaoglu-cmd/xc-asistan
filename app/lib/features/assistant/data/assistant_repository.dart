// SAHİBİ: assistant ajanı. Başka feature bu dosyaya yazmaz.
// Asistan veri erişimi. Uçlar (sözleşme A1, A2, B, C; taban adres zaten `/api` içerir):
//   Komut çubuğu: POST /assistant/commands, GET /assistant/commands/chips,
//     GET|PATCH /assistant/actions/:id, POST .../confirm|reject|undo
//   Brifing: GET /assistant/briefing/today, GET /assistant/briefings, POST .../:id/read
//   Müdür: GET /assistant/insights, POST .../:id/snooze|dismiss|applied|feedback,
//     GET|PUT /assistant/insight-rules (admin)
//   Kapanış: GET /assistant/closure/today, POST /assistant/closure/answers
//   Kutu/tercih: /assistant/inbox..., GET|PUT /assistant/prefs
//   Yazışma: /assistant/imports..., /suggestions, /conversations, /notes, /consents
//
// Kalıp: modeller bu klasörde elle yazılır (null-güvenli); metotlar AppException fırlatır.
import 'package:dio/dio.dart' show Options;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/api/api_providers.dart';
import '../../../core/util/json.dart';
import 'briefing_models.dart';
import 'closure_models.dart';
import 'command_models.dart';
import 'import_models.dart';
import 'inbox_models.dart';
import 'insight_models.dart';
import 'model_utils.dart';

abstract class AssistantRepository {
  // ---- Komut çubuğu ----
  Future<AssistantReply> sendCommand(
    String text, {
    Map<String, String>? choices,
  });
  Future<List<String>> commandChips();
  Future<ActionCard> getAction(String id);
  Future<ActionCard> editAction(String id, Map<String, Object?> fields);
  Future<ActionCard> confirmAction(String id);
  Future<ActionCard> rejectAction(String id);
  Future<ActionCard> undoAction(String id);

  // ---- Brifing ----
  Future<Briefing> briefingToday({bool refresh = false});
  Future<List<Briefing>> briefings({String? type, int limit = 20});
  Future<void> markBriefingRead(String id);

  // ---- Müdür ----
  Future<List<Insight>> insights({String status = 'acik'});
  Future<void> snoozeInsight(String id, int days);
  Future<void> dismissInsight(String id);
  Future<void> markInsightApplied(String id);
  Future<void> insightFeedback(String id, String verdict, {String? note});
  Future<InsightRulesConfig> insightRules();
  Future<InsightRulesConfig> updateInsightRules({
    List<({String key, bool? enabled, Map<String, int>? params})> rules,
    bool? calibrationMode,
  });

  // ---- Kapanış ----
  Future<ClosureState> closureToday({bool refresh = false});
  Future<ClosureResult> submitClosure({
    required String date,
    required List<ClosureAnswer> answers,
    String? freeNote,
    bool finish = false,
  });

  // ---- Kutu / tercih ----
  Future<InboxPage> inbox({
    bool unreadOnly = false,
    int limit = 30,
    String? before,
  });
  Future<int> inboxUnreadCount();
  Future<void> markInboxRead(String id);
  Future<void> markAllInboxRead();
  Future<void> ackInbox(String id);
  Future<AssistantPrefs> prefs();
  Future<AssistantPrefs> updatePrefs(Map<String, Object?> patch);

  // ---- Yazışma içe aktarma ----
  Future<ConsentNotice> consentNotice();
  Future<ImportPreview> importFile({
    required String path,
    required String name,
    required String consentVersion,
    String? customerKey,
  });
  Future<ImportPreview> importText({
    required String text,
    required String consentVersion,
  });
  Future<ImportConfirmResult> confirmImport(
    String id, {
    required String ownerSender,
    bool customerKeyGiven = false,
    String? customerKey,
    bool includeGroup = false,
  });
  Future<void> deleteImport(String id, {bool keepNotes = true});
  Future<List<Suggestion>> suggestions({
    String status = 'beklemede',
    String? conversationId,
    String? customerKey,
  });
  Future<SuggestionDecision> decideSuggestion(
    String id,
    String status, {
    Map<String, String>? fields,
  });
  Future<List<ConversationRef>> conversations({String? customerKey});
  Future<void> deleteConversation(String id);
  Future<List<AssistantNote>> customerNotes(String customerKey);
  Future<void> deleteCustomerData(String customerKey);
  Future<List<ConsentRecord>> consents();
  Future<void> withdrawConsent(String id);
  Future<List<CustomerHit>> searchCustomers(String q);

  // ---- Yardımcı ----
  /// Mesaj şablonunu çözer; bulunamazsa/başarısızsa null (çağıran hazır metne düşer).
  Future<RenderedMessage?> renderTemplate(
    String templateCode, {
    String? offerId,
    String? projectId,
    String? phone,
  });

  /// Sunucunun verdiği çağrı tarifini (PATCH/POST ...) çalıştırır.
  Future<Object?> callApply(String method, String path, Object? body);
}

class HttpAssistantRepository implements AssistantRepository {
  HttpAssistantRepository(this.api);
  final ApiClient api;

  static const _a = '/assistant';

  // ---------------- Komut çubuğu ----------------
  @override
  Future<AssistantReply> sendCommand(
    String text, {
    Map<String, String>? choices,
  }) async {
    final res = await api.send(
      'POST',
      '$_a/commands',
      data: {
        'text': text,
        if (choices != null && choices.isNotEmpty) 'choices': choices,
      },
    );
    return AssistantReply.fromJson(res.map);
  }

  @override
  Future<List<String>> commandChips() async {
    final m = asJsonMap(await api.get('$_a/commands/chips'));
    return [
      for (final c in (m['chips'] is List ? m['chips'] as List : const []))
        if (c is String) c else if (c is Map) asJsonMap(c).strOr('text'),
    ].where((e) => e.isNotEmpty).toList();
  }

  @override
  Future<ActionCard> getAction(String id) async =>
      ActionCard.fromJson(asJsonMap(await api.get('$_a/actions/$id')));

  @override
  Future<ActionCard> editAction(String id, Map<String, Object?> fields) async {
    final body = await api.patch('$_a/actions/$id', data: {'fields': fields});
    return ActionCard.fromResponse(body) ?? await getAction(id);
  }

  Future<ActionCard> _decide(String id, String verb) async {
    final res = await api.send(
      'POST',
      '$_a/actions/$id/$verb',
      // Aynı karta çift dokunma: sunucu ilk yanıtı aynen döner.
      options: Options(headers: {'Idempotency-Key': 'act-$verb-$id'}),
    );
    return ActionCard.fromResponse(res.data) ?? await getAction(id);
  }

  @override
  Future<ActionCard> confirmAction(String id) => _decide(id, 'confirm');
  @override
  Future<ActionCard> rejectAction(String id) => _decide(id, 'reject');
  @override
  Future<ActionCard> undoAction(String id) => _decide(id, 'undo');

  // ---------------- Brifing ----------------
  @override
  Future<Briefing> briefingToday({bool refresh = false}) async =>
      Briefing.fromJson(
        await api.getMap(
          '$_a/briefing/today',
          query: {if (refresh) 'refresh': 1},
        ),
      );

  @override
  Future<List<Briefing>> briefings({String? type, int limit = 20}) async {
    final raw = await api.get(
      '$_a/briefings',
      query: {'type': type, 'limit': limit},
    );
    final rows = raw is Map ? asJsonMap(raw).list('items') : asJsonList(raw);
    return [for (final r in rows) Briefing.fromJson(r)];
  }

  @override
  Future<void> markBriefingRead(String id) async {
    await api.post('$_a/briefings/$id/read');
  }

  // ---------------- Müdür ----------------
  @override
  Future<List<Insight>> insights({String status = 'acik'}) async {
    final m = asJsonMap(
      await api.get('$_a/insights', query: {'status': status, 'limit': 50}),
    );
    return [for (final i in m.list('items')) Insight.fromJson(i)];
  }

  @override
  Future<void> snoozeInsight(String id, int days) async {
    await api.post('$_a/insights/$id/snooze', data: {'days': days});
  }

  @override
  Future<void> dismissInsight(String id) async {
    await api.post('$_a/insights/$id/dismiss');
  }

  @override
  Future<void> markInsightApplied(String id) async {
    await api.post('$_a/insights/$id/applied');
  }

  @override
  Future<void> insightFeedback(
    String id,
    String verdict, {
    String? note,
  }) async {
    await api.post(
      '$_a/insights/$id/feedback',
      data: {
        'verdict': verdict,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
  }

  @override
  Future<InsightRulesConfig> insightRules() async =>
      InsightRulesConfig.fromJson(
        asJsonMap(await api.get('$_a/insight-rules')),
      );

  @override
  Future<InsightRulesConfig> updateInsightRules({
    List<({String key, bool? enabled, Map<String, int>? params})> rules =
        const [],
    bool? calibrationMode,
  }) async {
    final body = <String, Object?>{
      if (rules.isNotEmpty)
        'rules': [
          for (final r in rules)
            {
              'rule_key': r.key,
              if (r.enabled != null) 'enabled': r.enabled,
              if (r.params != null) 'params': r.params,
            },
        ],
      if (calibrationMode != null) 'calibration_mode': calibrationMode,
    };
    return InsightRulesConfig.fromJson(
      asJsonMap(await api.put('$_a/insight-rules', data: body)),
    );
  }

  // ---------------- Kapanış ----------------
  @override
  Future<ClosureState> closureToday({bool refresh = false}) async =>
      ClosureState.fromJson(
        await api.getMap(
          '$_a/closure/today',
          query: {if (refresh) 'refresh': 1},
        ),
      );

  @override
  Future<ClosureResult> submitClosure({
    required String date,
    required List<ClosureAnswer> answers,
    String? freeNote,
    bool finish = false,
  }) async {
    final res = await api.send(
      'POST',
      '$_a/closure/answers',
      data: {
        'date': date,
        'answers': [for (final a in answers) a.toJson()],
        if (freeNote != null && freeNote.trim().isNotEmpty)
          'free_note': freeNote.trim(),
        if (finish) 'finish': true,
      },
    );
    return ClosureResult.fromJson(res.map);
  }

  // ---------------- Kutu / tercih ----------------
  @override
  Future<InboxPage> inbox({
    bool unreadOnly = false,
    int limit = 30,
    String? before,
  }) async => InboxPage.fromJson(
    await api.getMap(
      '$_a/inbox',
      query: {if (unreadOnly) 'unread': 1, 'limit': limit, 'before': before},
    ),
  );

  @override
  Future<int> inboxUnreadCount() async => InboxPage.fromJson(
    await api.getMap('$_a/inbox', query: {'unread': 1, 'limit': 1}),
  ).unreadCount;

  @override
  Future<void> markInboxRead(String id) async {
    await api.post('$_a/inbox/$id/read');
  }

  @override
  Future<void> markAllInboxRead() async {
    await api.post('$_a/inbox/read-all');
  }

  @override
  Future<void> ackInbox(String id) async {
    await api.post('$_a/inbox/$id/ack');
  }

  @override
  Future<AssistantPrefs> prefs() async =>
      AssistantPrefs.fromJson(await api.getMap('$_a/prefs'));

  @override
  Future<AssistantPrefs> updatePrefs(Map<String, Object?> patch) async =>
      AssistantPrefs.fromJson(
        asJsonMap(await api.put('$_a/prefs', data: patch)),
      );

  // ---------------- Yazışma içe aktarma ----------------
  @override
  Future<ConsentNotice> consentNotice() async =>
      ConsentNotice.fromJson(await api.getMap('$_a/imports/consent-notice'));

  @override
  Future<ImportPreview> importFile({
    required String path,
    required String name,
    required String consentVersion,
    String? customerKey,
  }) async => ImportPreview.fromJson(
    await api.upload(
      '$_a/imports',
      field: 'file',
      filePath: path,
      fileName: name,
      fields: {
        'consent': 'true',
        'consent_version': consentVersion,
        if (customerKey != null && customerKey.isNotEmpty)
          'customer_key': customerKey,
      },
    ),
  );

  @override
  Future<ImportPreview> importText({
    required String text,
    required String consentVersion,
  }) async => ImportPreview.fromJson(
    asJsonMap(
      await api.post(
        '$_a/imports',
        data: {
          'text': text,
          'source': 'share',
          'consent': true,
          'consent_version': consentVersion,
        },
      ),
    ),
  );

  @override
  Future<ImportConfirmResult> confirmImport(
    String id, {
    required String ownerSender,
    bool customerKeyGiven = false,
    String? customerKey,
    bool includeGroup = false,
  }) async {
    final res = await api.send(
      'POST',
      '$_a/imports/$id/confirm',
      data: {
        'owner_sender': ownerSender,
        // Anahtar verilmezse sunucu en iyi eşleşmeyi kullanır; null → müşteriye bağlama.
        if (customerKeyGiven) 'customer_key': customerKey,
        if (includeGroup) 'include_group': true,
      },
    );
    return ImportConfirmResult.fromJson(res.map);
  }

  @override
  Future<void> deleteImport(String id, {bool keepNotes = true}) async {
    await api.delete(
      '$_a/imports/$id',
      query: {if (keepNotes) 'keep_notes': 1},
    );
  }

  @override
  Future<List<Suggestion>> suggestions({
    String status = 'beklemede',
    String? conversationId,
    String? customerKey,
  }) async {
    final raw = await api.get(
      '$_a/suggestions',
      query: {
        'status': status,
        'conversation_id': conversationId,
        'customer_key': customerKey,
      },
    );
    final rows = raw is Map ? asJsonMap(raw).list('items') : asJsonList(raw);
    return [for (final r in rows) Suggestion.fromJson(r)];
  }

  @override
  Future<SuggestionDecision> decideSuggestion(
    String id,
    String status, {
    Map<String, String>? fields,
  }) async {
    final body = await api.patch(
      '$_a/suggestions/$id',
      data: {
        'status': status,
        if (fields != null && fields.isNotEmpty) 'fields': fields,
      },
    );
    return SuggestionDecision.fromJson(asJsonMap(body));
  }

  @override
  Future<List<ConversationRef>> conversations({String? customerKey}) async {
    final raw = await api.get(
      '$_a/conversations',
      query: {'customer_key': customerKey},
    );
    final rows = raw is Map ? asJsonMap(raw).list('items') : asJsonList(raw);
    return [for (final r in rows) ConversationRef.fromJson(r)];
  }

  @override
  Future<void> deleteConversation(String id) async {
    await api.delete('$_a/conversations/$id');
  }

  @override
  Future<List<AssistantNote>> customerNotes(String customerKey) async {
    final raw = await api.get('$_a/customers/$customerKey/notes');
    final rows = raw is Map ? asJsonMap(raw).list('items') : asJsonList(raw);
    return [for (final r in rows) AssistantNote.fromJson(r)];
  }

  @override
  Future<void> deleteCustomerData(String customerKey) async {
    await api.delete('$_a/customers/$customerKey/data');
  }

  @override
  Future<List<ConsentRecord>> consents() async {
    final raw = await api.get('$_a/consents');
    final rows = raw is Map ? asJsonMap(raw).list('items') : asJsonList(raw);
    return [for (final r in rows) ConsentRecord.fromJson(r)];
  }

  @override
  Future<void> withdrawConsent(String id) async {
    await api.post('$_a/consents/$id/withdraw');
  }

  @override
  Future<List<CustomerHit>> searchCustomers(String q) async {
    final rows = await api.getList('/customers', query: {'q': q, 'limit': 20});
    return [
      for (final r in rows)
        if (CustomerHit.fromJson(r).key.isNotEmpty) CustomerHit.fromJson(r),
    ];
  }

  // ---------------- Yardımcı ----------------
  @override
  Future<RenderedMessage?> renderTemplate(
    String templateCode, {
    String? offerId,
    String? projectId,
    String? phone,
  }) async {
    try {
      final list = await api.getList('/message-templates', query: {'all': 1});
      JsonMap? hit;
      for (final t in list) {
        final code = t.str('code') ?? t.str('key') ?? t.str('slug');
        if (code == templateCode) {
          hit = t;
          break;
        }
      }
      final id = hit?.str('id');
      if (id == null) return null;
      final res = await api.post(
        '/message-templates/$id/render',
        data: {'offer_id': offerId, 'project_id': projectId, 'phone': phone}
          ..removeWhere((_, v) => v == null),
      );
      final r = RenderedMessage.fromJson(asJsonMap(res));
      return r.text.isEmpty ? null : r;
    } on AppException {
      return null;
    }
  }

  @override
  Future<Object?> callApply(String method, String path, Object? body) async {
    final res = await api.send(
      method.toUpperCase(),
      relativeApiPath(path),
      data: body,
    );
    return res.data;
  }
}

final assistantRepositoryProvider = Provider<AssistantRepository>(
  (ref) => HttpAssistantRepository(ref.watch(apiClientProvider)),
);
