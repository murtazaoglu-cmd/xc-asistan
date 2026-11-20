// Komut çubuğu ve onay kartı modelleri (sözleşme C §2).
import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/json.dart';
import 'model_utils.dart';

@immutable
class ChoiceOption {
  const ChoiceOption({required this.value, required this.label});
  final String value;
  final String label;

  factory ChoiceOption.fromJson(Object? raw) {
    if (raw is Map) {
      final j = asJsonMap(raw);
      final v = j.str('value') ?? j.str('key') ?? j.str('id') ?? '';
      return ChoiceOption(
        value: v,
        label: j.strOrNull('label') ?? j.strOrNull('name') ?? v,
      );
    }
    final s = raw?.toString() ?? '';
    return ChoiceOption(value: s, label: s);
  }

  static List<ChoiceOption> list(Object? v) => v is List
      ? v.map(ChoiceOption.fromJson).where((o) => o.value.isNotEmpty).toList()
      : const [];
}

/// Kart durumu (sözleşme: onerildi → onaylandi → uygulandi | hata; reddedildi; geri_alindi; suresi_doldu).
enum CardStatus {
  onerildi('onerildi', 'Bekliyor'),
  onaylandi('onaylandi', 'Uygulanıyor'),
  uygulandi('uygulandi', 'Uygulandı'),
  hata('hata', 'Hata'),
  reddedildi('reddedildi', 'Reddedildi'),
  geriAlindi('geri_alindi', 'Geri alındı'),
  suresiDoldu('suresi_doldu', 'Süresi doldu'),
  bilinmiyor('', 'Bilinmiyor');

  const CardStatus(this.api, this.label);
  final String api;
  final String label;

  static CardStatus fromApi(String? v) {
    for (final s in values) {
      if (s.api == v) return s;
    }
    return bilinmiyor;
  }

  /// Karar verilmiş / kapanmış mı?
  bool get isFinal => this != onerildi && this != onaylandi;
}

@immutable
class CardField {
  const CardField({
    required this.key,
    required this.label,
    required this.type,
    this.value,
    this.display,
    this.editable = false,
    this.options = const [],
  });

  final String key;
  final String label;

  /// text | number | money | date | time | datetime | choice (bilinmeyen → text)
  final String type;
  final Object? value;
  final String? display;
  final bool editable;
  final List<ChoiceOption> options;

  String get shownValue => display ?? (value == null ? '' : value.toString());

  factory CardField.fromJson(JsonMap j) => CardField(
    key: j.strOr('key'),
    label: j.strOrNull('label') ?? j.strOr('key'),
    type: j.strOr('type', 'text'),
    value: j['value'],
    display: j.strOrNull('display'),
    editable: j.boolOr('editable'),
    options: ChoiceOption.list(j['options']),
  );
}

@immutable
class UndoInfo {
  const UndoInfo({this.available = false, this.until, this.reason});
  final bool available;
  final DateTime? until;
  final String? reason;

  factory UndoInfo.fromJson(JsonMap? j) => j == null
      ? const UndoInfo()
      : UndoInfo(
          available: j.boolOr('available'),
          until: j.dateTime('until'),
          reason: j.strOrNull('reason'),
        );
}

@immutable
class ActionCard {
  const ActionCard({
    required this.id,
    this.origin = 'command_bar',
    this.intent = '',
    this.risk,
    this.status = CardStatus.onerildi,
    this.text = '',
    this.summary,
    this.fields = const [],
    this.ambiguities = const [],
    this.warnings = const [],
    this.result,
    this.error,
    this.undo = const UndoInfo(),
    this.createdAt,
    this.expiresAt,
    this.appliedAt,
  });

  final String id;
  final String origin;
  final String intent;
  final String? risk;
  final CardStatus status;
  final String text;
  final String? summary;
  final List<CardField> fields;
  final List<String> ambiguities;
  final List<String> warnings;
  final Object? result;
  final String? error;
  final UndoInfo undo;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? appliedAt;

  bool get isPending => status == CardStatus.onerildi;
  bool get hasEditable => fields.any((f) => f.editable);
  String get title =>
      (summary != null && summary!.isNotEmpty) ? summary! : text;

  bool canUndo([DateTime? now]) {
    if (status != CardStatus.uygulandi || !undo.available) return false;
    final until = undo.until;
    return until == null || until.isAfter(now ?? Ist.now());
  }

  bool isExpired([DateTime? now]) {
    if (status == CardStatus.suresiDoldu) return true;
    final e = expiresAt;
    return isPending && e != null && e.isBefore(now ?? Ist.now());
  }

  factory ActionCard.fromJson(JsonMap j) => ActionCard(
    id: j.strOr('id'),
    origin: j.strOr('origin', 'command_bar'),
    intent: j.strOr('intent'),
    risk: j.strOrNull('risk'),
    status: CardStatus.fromApi(j.str('status')),
    text: j.strOr('text'),
    summary: j.strOrNull('summary'),
    fields: [for (final f in j.list('fields')) CardField.fromJson(f)],
    ambiguities: readStrings(j['ambiguities']),
    warnings: readStrings(j['warnings']),
    result: j['result'],
    error: j.strOrNull('error'),
    undo: UndoInfo.fromJson(j.mapOrNull('undo')),
    createdAt: j.dateTime('created_at'),
    expiresAt: j.dateTime('expires_at'),
    appliedAt: j.dateTime('applied_at'),
  );

  /// confirm/undo/reject yanıtı: kartın kendisi ya da `{action: Card}`.
  static ActionCard? fromResponse(Object? body) {
    final m = asJsonMap(body);
    final inner = m.mapOrNull('action') ?? m.mapOrNull('card');
    if (inner != null) return ActionCard.fromJson(inner);
    if (m['id'] != null && m['status'] != null) return ActionCard.fromJson(m);
    return null;
  }
}

@immutable
class ClarifyQuestion {
  const ClarifyQuestion({
    required this.field,
    required this.type,
    required this.label,
    this.options = const [],
  });
  final String field;

  /// choice | text | date | time
  final String type;
  final String label;
  final List<ChoiceOption> options;

  factory ClarifyQuestion.fromJson(JsonMap j) => ClarifyQuestion(
    field: j.strOr('field'),
    type: j.strOr('type', 'choice'),
    label: j.strOrNull('label') ?? j.strOr('field'),
    options: ChoiceOption.list(j['options']),
  );
}

enum ReplyKind { answer, actionCard, clarify }

/// `POST /assistant/commands` yanıtı.
@immutable
class AssistantReply {
  const AssistantReply({
    required this.kind,
    this.intent = '',
    this.text = '',
    this.data = const {},
    this.refused = false,
    this.reason,
    this.chips = const [],
    this.card,
    this.questions = const [],
  });

  final ReplyKind kind;
  final String intent;
  final String text;
  final JsonMap data;
  final bool refused;
  final String? reason;
  final List<String> chips;
  final ActionCard? card;
  final List<ClarifyQuestion> questions;

  /// Ayrıştırıcı komutu anlamadı: "Ne demek istediniz?" seçenek kartı gösterilir.
  bool get isUnknown => intent == 'unknown';

  factory AssistantReply.fromJson(JsonMap j) {
    final kindRaw = j.strOr('kind', 'answer');
    final chips = <String>[
      for (final c in (j['chips'] is List ? j['chips'] as List : const []))
        if (c is String && c.trim().isNotEmpty)
          c.trim()
        else if (c is Map)
          (asJsonMap(c).strOrNull('text') ??
                  asJsonMap(c).strOrNull('label') ??
                  asJsonMap(c).strOrNull('command') ??
                  '')
              .trim(),
    ].where((s) => s.isNotEmpty).toList();
    switch (kindRaw) {
      case 'action_card':
        final card = j.mapOrNull('action');
        return AssistantReply(
          kind: ReplyKind.actionCard,
          intent: card?.strOr('intent') ?? j.strOr('intent'),
          card: card == null ? null : ActionCard.fromJson(card),
          text: card?.strOr('text') ?? '',
          chips: chips,
        );
      case 'clarify':
        return AssistantReply(
          kind: ReplyKind.clarify,
          intent: j.strOr('intent'),
          reason: j.strOrNull('reason'),
          text: j.strOrNull('message') ?? j.strOr('text'),
          questions: [
            for (final q in j.list('questions')) ClarifyQuestion.fromJson(q),
          ],
          chips: chips,
        );
      default:
        return AssistantReply(
          kind: ReplyKind.answer,
          intent: j.strOr('intent'),
          text: j.strOr('text'),
          data: j.mapOrNull('data') ?? const {},
          refused: j.boolOr('refused'),
          reason: j.strOrNull('reason'),
          chips: chips,
        );
    }
  }
}
