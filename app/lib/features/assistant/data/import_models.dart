// Yazışma içe aktarma (sözleşme C §3): rıza metni, önizleme, öneriler, notlar.
import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/json.dart';
import 'command_models.dart';
import 'model_utils.dart';

@immutable
class ConsentNotice {
  const ConsentNotice({
    required this.version,
    required this.title,
    required this.paragraphs,
    required this.checkbox,
  });
  final String version;
  final String title;
  final List<String> paragraphs;
  final String checkbox;

  factory ConsentNotice.fromJson(JsonMap j) => ConsentNotice(
    version: j.strOr('version'),
    title: j.strOr('title', 'Aydınlatma ve rıza'),
    paragraphs: readStrings(j['text'] is String ? [j['text']] : j['text']),
    checkbox: j.strOr(
      'checkbox',
      'Okudum, yazışmanın işlenmesine onay veriyorum.',
    ),
  );
}

/// Eşleşme adayı müşteri.
@immutable
class CustomerCandidate {
  const CustomerCandidate({required this.key, required this.name, this.phone});
  final String key;
  final String name;
  final String? phone;

  factory CustomerCandidate.fromJson(JsonMap j) => CustomerCandidate(
    key: j.str('customer_key') ?? j.str('phone_key') ?? j.strOr('key'),
    name:
        j.strOrNull('name') ?? j.strOrNull('customer_name') ?? j.strOr('phone'),
    phone: j.strOrNull('phone'),
  );
}

@immutable
class PreviewMessage {
  const PreviewMessage({required this.sender, required this.text, this.sentAt});
  final String sender;
  final String text;
  final DateTime? sentAt;

  static PreviewMessage? from(JsonMap? j) => j == null
      ? null
      : PreviewMessage(
          sender: j.strOrNull('sender') ?? j.strOr('from'),
          text: j.strOrNull('text') ?? j.strOr('body'),
          sentAt: j.dateTime('sent_at') ?? j.dateTime('at') ?? j.dateTime('ts'),
        );
}

@immutable
class ImportPreview {
  const ImportPreview({
    required this.id,
    this.fileName,
    this.messageCount = 0,
    this.participants = const [],
    this.isGroup = false,
    this.suggestedOwner,
    this.candidates = const [],
    this.customer,
    this.alreadyImported = false,
    this.singleMessage = false,
    this.warnings = const [],
    this.first,
    this.last,
    this.from,
    this.to,
    this.suggestionCounts = const {},
    this.expiresAt,
  });
  final String id;
  final String? fileName;
  final int messageCount;
  final List<String> participants;
  final bool isGroup;
  final String? suggestedOwner;
  final List<CustomerCandidate> candidates;

  /// Sunucunun en iyi eşleşmesi (varsa).
  final CustomerCandidate? customer;
  final bool alreadyImported;
  final bool singleMessage;
  final List<String> warnings;
  final PreviewMessage? first;
  final PreviewMessage? last;
  final DateTime? from;
  final DateTime? to;
  final Map<String, int> suggestionCounts;
  final DateTime? expiresAt;

  int get suggestionTotal => suggestionCounts.values.fold(0, (a, b) => a + b);

  /// Tarih aralığı: istatistik alanından, yoksa ilk/son mesajdan.
  ({DateTime? from, DateTime? to}) get range =>
      (from: from ?? first?.sentAt, to: to ?? last?.sentAt);

  factory ImportPreview.fromJson(JsonMap j) {
    final stats = j.mapOrNull('stats') ?? const <String, dynamic>{};
    final pm = j.mapOrNull('preview_messages');
    final cust = j.mapOrNull('customer');
    final counts = <String, int>{};
    asJsonMap(j['suggestion_counts']).forEach((k, v) {
      final n = v is num ? v.toInt() : int.tryParse('$v');
      if (n != null) counts[k] = n;
    });
    final parts = <String>[
      for (final p
          in (j['participants'] is List ? j['participants'] as List : const []))
        if (p is String) p else if (p is Map) asJsonMap(p).strOr('name'),
    ].where((e) => e.isNotEmpty).toList();
    return ImportPreview(
      id: j.strOr('id'),
      fileName: j.mapOrNull('file')?.strOrNull('name') ?? j.strOrNull('file'),
      messageCount: stats.intOr('messages', stats.intOr('message_count')),
      participants: parts,
      isGroup: j.boolOr('is_group'),
      suggestedOwner: j.strOrNull('suggested_owner_sender'),
      candidates: [
        for (final c in j.list('candidates')) CustomerCandidate.fromJson(c),
      ],
      customer: cust == null ? null : CustomerCandidate.fromJson(cust),
      alreadyImported: j.boolOr('already_imported'),
      singleMessage: j.boolOr('single_message'),
      warnings: readStrings(j['warnings']),
      first: PreviewMessage.from(pm?.mapOrNull('first')),
      last: PreviewMessage.from(pm?.mapOrNull('last')),
      from:
          stats.dateTime('first_at') ??
          stats.dateTime('from') ??
          stats.dateTime('date_from'),
      to:
          stats.dateTime('last_at') ??
          stats.dateTime('to') ??
          stats.dateTime('date_to'),
      suggestionCounts: counts,
      expiresAt: j.dateTime('expires_at'),
    );
  }
}

@immutable
class ImportConfirmResult {
  const ImportConfirmResult({
    required this.already,
    this.conversationId,
    this.inserted = 0,
    this.duplicates = 0,
    this.suggestionsCreated = 0,
  });
  final bool already;
  final String? conversationId;
  final int inserted;
  final int duplicates;
  final int suggestionsCreated;

  factory ImportConfirmResult.fromJson(JsonMap j) => ImportConfirmResult(
    already: j.boolOr('already'),
    conversationId: j.strOrNull('conversation_id'),
    inserted: j.intOr('inserted'),
    duplicates: j.intOr('duplicates'),
    suggestionsCreated: j.intOr('suggestions_created'),
  );
}

enum SuggestionKind {
  note('not', 'Not'),
  reminder('hatirlatma', 'Hatırlatma'),
  appointment('randevu', 'Randevu'),
  unknown('', 'Öneri');

  const SuggestionKind(this.api, this.label);
  final String api;
  final String label;
  static SuggestionKind fromApi(String? v) {
    for (final k in values) {
      if (k.api == v) return k;
    }
    return unknown;
  }
}

/// Kural tabanlı öneri; her biri kaynak mesaja bağlıdır.
@immutable
class Suggestion {
  const Suggestion({
    required this.id,
    required this.kind,
    required this.status,
    required this.text,
    this.title,
    this.fields = const {},
    this.sourceText,
    this.sourceSender,
    this.sourceAt,
    this.sourceRef,
    this.conversationId,
    this.customerKey,
  });
  final String id;
  final SuggestionKind kind;

  /// beklemede | kabul | red
  final String status;
  final String text;
  final String? title;

  /// Düzenlenebilir alanlar (metin değerleri).
  final Map<String, String> fields;
  final String? sourceText;
  final String? sourceSender;
  final DateTime? sourceAt;
  final String? sourceRef;
  final String? conversationId;
  final String? customerKey;

  bool get isPending => status == 'beklemede';

  factory Suggestion.fromJson(JsonMap j) {
    final src =
        j.mapOrNull('source') ??
        j.mapOrNull('message') ??
        j.mapOrNull('source_message');
    final f = <String, String>{};
    final rawFields = j['fields'];
    if (rawFields is Map) {
      asJsonMap(rawFields).forEach((k, v) {
        if (v == null || v is Map || v is List) return;
        f[k] = v.toString();
      });
    } else if (rawFields is List) {
      for (final e in asJsonList(rawFields)) {
        final k = e.strOr('key');
        final v = e['value'];
        if (k.isNotEmpty && v != null && v is! Map && v is! List)
          f[k] = v.toString();
      }
    }
    return Suggestion(
      id: j.strOr('id'),
      kind: SuggestionKind.fromApi(j.str('kind')),
      status: j.strOr('status', 'beklemede'),
      text: j.strOrNull('text') ?? j.strOrNull('summary') ?? j.strOr('title'),
      title: j.strOrNull('title'),
      fields: f,
      sourceText:
          src?.strOrNull('text') ??
          j.strOrNull('source_text') ??
          j.strOrNull('evidence') ??
          j.strOrNull('quote'),
      sourceSender: src?.strOrNull('sender') ?? j.strOrNull('source_sender'),
      sourceAt: src?.dateTime('sent_at') ?? src?.dateTime('at'),
      sourceRef:
          j.strOrNull('message_ref') ??
          j.strOrNull('source_ref') ??
          j.strOrNull('message_id') ??
          src?.strOrNull('id'),
      conversationId: j.strOrNull('conversation_id'),
      customerKey: j.strOrNull('customer_key'),
    );
  }
}

/// `PATCH /suggestions/:id` sonucu: karar + (randevu kabulünde) onay kartı.
@immutable
class SuggestionDecision {
  const SuggestionDecision({this.suggestion, this.card, this.replayed = false});
  final Suggestion? suggestion;
  final ActionCard? card;
  final bool replayed;

  factory SuggestionDecision.fromJson(JsonMap j) {
    final card = j.mapOrNull('action') ?? j.mapOrNull('card');
    final s = j.mapOrNull('suggestion') ?? (j['kind'] != null ? j : null);
    return SuggestionDecision(
      suggestion: s == null ? null : Suggestion.fromJson(s),
      card: card == null ? null : ActionCard.fromJson(card),
      replayed: j.boolOr('replayed'),
    );
  }
}

@immutable
class ConversationRef {
  const ConversationRef({
    required this.id,
    required this.title,
    this.messageCount = 0,
    this.lastAt,
    this.from,
    this.to,
    this.summaryText,
  });
  final String id;
  final String title;
  final int messageCount;
  final DateTime? lastAt;
  final DateTime? from;
  final DateTime? to;

  /// "Son durum" özeti (varsa).
  final String? summaryText;

  factory ConversationRef.fromJson(JsonMap j) => ConversationRef(
    id: j.strOr('id'),
    title: j.strOrNull('title') ?? j.strOrNull('name') ?? 'Yazışma',
    messageCount: j.intOr('message_count', j.intOr('messages')),
    lastAt: j.dateTime('last_message_at') ?? j.dateTime('updated_at'),
    from: j.dateTime('first_message_at') ?? j.dateTime('from'),
    to: j.dateTime('last_message_at') ?? j.dateTime('to'),
    summaryText: j.strOrNull('summary') ?? j.strOrNull('last_state'),
  );
}

@immutable
class AssistantNote {
  const AssistantNote({
    required this.id,
    required this.text,
    this.author,
    this.tags = const [],
    this.createdAt,
  });
  final String id;
  final String text;

  /// user | rule
  final String? author;
  final List<String> tags;
  final DateTime? createdAt;

  bool get byRule => author == 'rule';

  factory AssistantNote.fromJson(JsonMap j) => AssistantNote(
    id: j.strOr('id'),
    text: j.strOrNull('text') ?? j.strOr('body'),
    author: j.strOrNull('author'),
    tags: j.stringList('tags').isNotEmpty
        ? j.stringList('tags')
        : readStrings(j['labels']),
    createdAt: j.dateTime('created_at'),
  );
}

@immutable
class ConsentRecord {
  const ConsentRecord({
    required this.id,
    required this.type,
    this.version,
    this.givenAt,
    this.withdrawnAt,
  });
  final String id;
  final String type;
  final String? version;
  final DateTime? givenAt;
  final DateTime? withdrawnAt;
  bool get active => withdrawnAt == null;

  String get typeLabel => switch (type) {
    'aydinlatma' => 'Aydınlatma metni',
    'acik_riza' => 'Açık rıza',
    'veri_isleme_ack' => 'Veri işleme onayı',
    'ticari_ileti' => 'Ticari ileti',
    _ => type,
  };

  factory ConsentRecord.fromJson(JsonMap j) => ConsentRecord(
    id: j.strOr('id'),
    type: j.strOr('type'),
    version: j.strOrNull('version'),
    givenAt: j.dateTime('created_at') ?? j.dateTime('given_at'),
    withdrawnAt: j.dateTime('withdrawn_at'),
  );
}

/// Müşteri eşleme sihirbazı için arama sonucu.
@immutable
class CustomerHit {
  const CustomerHit({required this.key, required this.name, this.phone});
  final String key;
  final String name;
  final String? phone;

  factory CustomerHit.fromJson(JsonMap j) {
    final phone = j.strOrNull('phone') ?? j.strOrNull('customer_phone');
    final key =
        j.strOrNull('phone_key') ?? j.strOrNull('customer_key') ?? phone ?? '';
    return CustomerHit(
      key: assistantCustomerKey(key),
      name: j.strOrNull('name') ?? j.strOrNull('customer_name') ?? phone ?? '',
      phone: phone,
    );
  }
}

/// `POST /message-templates/:id/render` sonucu.
@immutable
class RenderedMessage {
  const RenderedMessage({
    required this.text,
    this.whatsappUrl,
    this.phone,
    this.missing = const [],
    this.complete = true,
  });
  final String text;
  final String? whatsappUrl;
  final String? phone;
  final List<String> missing;
  final bool complete;

  factory RenderedMessage.fromJson(JsonMap j) => RenderedMessage(
    text: j.strOr('text'),
    whatsappUrl: j.strOrNull('whatsappUrl'),
    phone: j.strOrNull('phone'),
    missing: j.stringList('missing'),
    complete: j.boolOr('complete', true),
  );
}

DateTime? parseWhen(String? s) => Ist.tryParse(s);
