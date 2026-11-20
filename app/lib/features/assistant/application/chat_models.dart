// Sohbet ekranı durum modelleri ve yerel geçmiş (shared_preferences).
// Gizlilik: yalnız KISA metinler saklanır (en çok 30 ileti, 7 gün); kart alanları (telefon, tutar
// ayrıntısı) ve yanıt `data` içeriği saklanmaz. Kullanıcıya göre ayrı anahtar; çıkışta temizlenir.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/json.dart';
import '../data/command_models.dart';

enum ChatRole { user, assistant }

/// text: düz balon · answer: yanıt (+sayı kartları) · card: onay kartı · clarify: seçenek soruları ·
/// options: "Ne demek istediniz?" kartı · error: hata balonu.
enum ChatKind { text, answer, card, clarify, options, error }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.kind,
    required this.text,
    required this.createdAt,
    this.data = const {},
    this.chips = const [],
    this.card,
    this.cardId,
    this.cardStatus,
    this.questions = const [],
    this.originalText,
    this.priorChoices = const {},
    this.answers = const {},
    this.resolved = false,
    this.refused = false,
    this.retryText,
    this.retryChoices = const {},
  });

  final String id;
  final ChatRole role;
  final ChatKind kind;
  final String text;
  final DateTime createdAt;

  /// Yanıt verisi (sayı kartları). KALICI DEĞİL.
  final JsonMap data;
  final List<String> chips;

  /// Onay kartı (yüklüyse). Geri yüklenen mesajda önce null, sonra sunucudan dolar.
  final ActionCard? card;
  final String? cardId;

  /// Kalıcı kart durumu (CardStatus.api).
  final String? cardStatus;

  // clarify
  final List<ClarifyQuestion> questions;
  final String? originalText;
  final Map<String, String> priorChoices;
  final Map<String, String> answers;
  final bool resolved;
  final bool refused;

  // error: tekrar denemek için
  final String? retryText;
  final Map<String, String> retryChoices;

  bool get isUser => role == ChatRole.user;

  ChatMessage copyWith({
    ActionCard? card,
    String? cardStatus,
    Map<String, String>? answers,
    bool? resolved,
    String? text,
  }) => ChatMessage(
    id: id,
    role: role,
    kind: kind,
    text: text ?? this.text,
    createdAt: createdAt,
    data: data,
    chips: chips,
    card: card ?? this.card,
    cardId: cardId,
    cardStatus: cardStatus ?? this.cardStatus,
    questions: questions,
    originalText: originalText,
    priorChoices: priorChoices,
    answers: answers ?? this.answers,
    resolved: resolved ?? this.resolved,
    refused: refused,
    retryText: retryText,
    retryChoices: retryChoices,
  );

  /// Kalıcı biçim (kısa).
  JsonMap toStored() => {
    'id': id,
    'role': role.name,
    'kind': kind.name,
    'text': text.length > 400 ? text.substring(0, 400) : text,
    'at': createdAt.toIso8601String(),
    if (chips.isNotEmpty) 'chips': chips,
    if (cardId != null) 'card_id': cardId,
    if (cardStatus != null) 'card_status': cardStatus,
    if (resolved) 'resolved': true,
    if (refused) 'refused': true,
  };

  static ChatMessage? fromStored(JsonMap j) {
    final id = j.strOr('id');
    if (id.isEmpty) return null;
    final kind = ChatKind.values
        .where((k) => k.name == j.str('kind'))
        .firstOrNull;
    final at = j.dateTime('at');
    if (kind == null || at == null) return null;
    return ChatMessage(
      id: id,
      role: j.str('role') == 'user' ? ChatRole.user : ChatRole.assistant,
      // Geri yüklenen soru kartları cevaplanamaz: düz balona döner.
      kind: kind == ChatKind.clarify ? ChatKind.text : kind,
      text: j.strOr('text'),
      createdAt: at,
      chips: j.stringList('chips'),
      cardId: j.strOrNull('card_id'),
      cardStatus: j.strOrNull('card_status'),
      resolved: j.boolOr('resolved'),
      refused: j.boolOr('refused'),
    );
  }
}

/// Sohbet ekranı durumu.
@immutable
class ChatState {
  const ChatState({
    this.messages = const [],
    this.sending = false,
    this.busyCards = const {},
    this.cardErrors = const {},
    this.pendingEdits = const {},
    this.notice,
  });
  final List<ChatMessage> messages;
  final bool sending;

  /// İşlem süren kart kimlikleri (çift dokunmayı engeller).
  final Set<String> busyCards;
  final Map<String, String> cardErrors;

  /// Henüz sunucuya yazılmamış düzenlemeler (Onayla'da önce PATCH edilir).
  final Map<String, Map<String, Object?>> pendingEdits;
  final String? notice;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? sending,
    Set<String>? busyCards,
    Map<String, String>? cardErrors,
    Map<String, Map<String, Object?>>? pendingEdits,
    String? notice,
    bool clearNotice = false,
  }) => ChatState(
    messages: messages ?? this.messages,
    sending: sending ?? this.sending,
    busyCards: busyCards ?? this.busyCards,
    cardErrors: cardErrors ?? this.cardErrors,
    pendingEdits: pendingEdits ?? this.pendingEdits,
    notice: clearNotice ? null : (notice ?? this.notice),
  );
}

/// Yerel sohbet geçmişi.
class ChatHistoryStore {
  ChatHistoryStore(this._prefs);
  final SharedPreferences _prefs;

  static const keyPrefix = 'assistant.chat.v1.';
  static const maxMessages = 30;
  static const maxAge = Duration(days: 7);

  String _key(String userId) => '$keyPrefix$userId';

  List<ChatMessage> load(String userId, {DateTime? now}) {
    final raw = _prefs.getString(_key(userId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final cutoff = (now ?? Ist.now()).subtract(maxAge);
      final out = <ChatMessage>[];
      for (final e in list) {
        final m = ChatMessage.fromStored(asJsonMap(e));
        if (m != null && m.createdAt.isAfter(cutoff)) out.add(m);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(String userId, List<ChatMessage> messages) async {
    final keep = [
      for (final m in messages)
        if (m.kind != ChatKind.error) m,
    ];
    final tail = keep.length > maxMessages
        ? keep.sublist(keep.length - maxMessages)
        : keep;
    await _prefs.setString(
      _key(userId),
      jsonEncode([for (final m in tail) m.toStored()]),
    );
  }

  Future<void> clear(String userId) => _prefs.remove(_key(userId));

  /// Çıkışta: tüm kullanıcıların sohbet geçmişi silinir.
  Future<void> clearAll() async {
    for (final k
        in _prefs.getKeys().where((k) => k.startsWith(keyPrefix)).toList()) {
      await _prefs.remove(k);
    }
  }
}
