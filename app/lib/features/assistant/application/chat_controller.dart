// Sohbet denetleyicisi: komut gönder → yanıt türü (answer / action_card / clarify) → onay, düzenle,
// vazgeç, geri al. Yapay zekâ YOK: sunucudaki kural tabanlı ayrıştırıcı kullanılır.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/util/dates.dart';
import '../data/assistant_repository.dart';
import '../data/command_models.dart';
import 'chat_models.dart';

final chatHistoryStoreProvider = Provider<ChatHistoryStore>(
  (ref) => ChatHistoryStore(ref.watch(sharedPreferencesProvider)),
);

/// Komut en çok 500 karakter (sözleşme C).
const int maxCommandLength = 500;

/// Sunucu "anlamadım" derken seçenek vermezse gösterilecek örnekler.
const List<String> fallbackCommandExamples = [
  'Bugün ne var?',
  'Yarın 10\'da randevu ekle',
  'Bu ay ne kadar tahsilat?',
];

class ChatNotifier extends Notifier<ChatState> {
  int _seq = 0;

  AssistantRepository get _repo => ref.read(assistantRepositoryProvider);
  String get _userId => ref.read(currentUserProvider)?.id ?? 'anon';

  @override
  ChatState build() {
    // Oturum kapanınca yerel geçmiş silinir.
    ref.listen(sessionProvider, (prev, next) {
      // Yalnız oturum AÇIKKEN kapanırsa (çıkış / jeton düşmesi) silinir; açılış sırasındaki geçiş değil.
      if (prev is SessionAuthenticated && next is SessionUnauthenticated) {
        ref.read(chatHistoryStoreProvider).clearAll();
        state = const ChatState();
      }
    });
    final stored = ref.read(chatHistoryStoreProvider).load(_userId);
    if (stored.any(
      (m) => m.cardId != null && m.cardStatus == CardStatus.onerildi.api,
    )) {
      Future<void>.microtask(_rehydratePending);
    }
    return ChatState(messages: stored);
  }

  String _id(String p) => '$p${Ist.now().microsecondsSinceEpoch}-${_seq++}';

  void _set(ChatState s, {bool persist = true}) {
    state = s;
    if (persist) {
      ref.read(chatHistoryStoreProvider).save(_userId, s.messages);
    }
  }

  void _add(ChatMessage m) =>
      _set(state.copyWith(messages: [...state.messages, m]));

  /// Yeniden açılışta bekleyen kartları sunucudan tazeler (süresi dolmuş olabilir).
  Future<void> _rehydratePending() async {
    for (final m in List<ChatMessage>.of(state.messages)) {
      if (m.cardId == null || m.card != null) continue;
      try {
        final c = await _repo.getAction(m.cardId!);
        _replaceCard(c);
      } on Object {
        _patchMessage(
          m.id,
          (x) => x.copyWith(cardStatus: CardStatus.suresiDoldu.api),
        );
      }
    }
  }

  void _patchMessage(String id, ChatMessage Function(ChatMessage) fn) {
    _set(
      state.copyWith(
        messages: [for (final m in state.messages) m.id == id ? fn(m) : m],
      ),
    );
  }

  void _replaceCard(ActionCard c) {
    _set(
      state.copyWith(
        messages: [
          for (final m in state.messages)
            m.cardId == c.id
                ? m.copyWith(card: c, cardStatus: c.status.api)
                : m,
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ komut gönder

  /// [choices] "ne demek istediniz?" cevabıdır; [userBubble] ekranda kullanıcı balonu olarak görünür.
  Future<void> send(
    String raw, {
    Map<String, String> choices = const {},
    String? userBubble,
    bool echo = true,
  }) async {
    final text = raw.trim();
    if (text.isEmpty || state.sending) return;
    if (text.length > maxCommandLength) {
      _set(
        state.copyWith(
          notice: 'Komut en çok $maxCommandLength karakter olabilir.',
        ),
        persist: false,
      );
      return;
    }
    if (echo) {
      _add(
        ChatMessage(
          id: _id('u'),
          role: ChatRole.user,
          kind: ChatKind.text,
          text: userBubble ?? text,
          createdAt: Ist.now(),
        ),
      );
    }
    state = state.copyWith(sending: true, clearNotice: true);
    try {
      final reply = await _repo.sendCommand(text, choices: choices);
      _add(_fromReply(reply, text, choices));
    } on Object catch (e) {
      final ex = AppException.from(e);
      _add(
        ChatMessage(
          id: _id('e'),
          role: ChatRole.assistant,
          kind: ChatKind.error,
          text: ex.message,
          createdAt: Ist.now(),
          retryText: ex.isRetryable ? text : null,
          retryChoices: choices,
        ),
      );
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  ChatMessage _fromReply(
    AssistantReply r,
    String text,
    Map<String, String> choices,
  ) {
    final now = Ist.now();
    switch (r.kind) {
      case ReplyKind.actionCard:
        final c = r.card;
        if (c == null) {
          return ChatMessage(
            id: _id('a'),
            role: ChatRole.assistant,
            kind: ChatKind.error,
            text: 'Kart hazırlanamadı. Lütfen komutu başka biçimde yazın.',
            createdAt: now,
          );
        }
        return ChatMessage(
          id: _id('a'),
          role: ChatRole.assistant,
          kind: ChatKind.card,
          text: c.title,
          createdAt: now,
          card: c,
          cardId: c.id,
          cardStatus: c.status.api,
        );
      case ReplyKind.clarify:
        if (r.questions.isEmpty || r.isUnknown) {
          return ChatMessage(
            id: _id('a'),
            role: ChatRole.assistant,
            kind: ChatKind.options,
            text: r.text.isEmpty ? 'Ne demek istediniz?' : r.text,
            createdAt: now,
            chips: r.chips.isEmpty ? fallbackCommandExamples : r.chips,
          );
        }
        return ChatMessage(
          id: _id('a'),
          role: ChatRole.assistant,
          kind: ChatKind.clarify,
          text: r.text.isEmpty ? 'Ne demek istediniz?' : r.text,
          createdAt: now,
          questions: r.questions,
          originalText: text,
          priorChoices: choices,
          chips: r.chips,
        );
      case ReplyKind.answer:
        if (r.isUnknown) {
          return ChatMessage(
            id: _id('a'),
            role: ChatRole.assistant,
            kind: ChatKind.options,
            text: r.text.isEmpty ? 'Ne demek istediniz?' : r.text,
            createdAt: now,
            chips: r.chips.isEmpty ? fallbackCommandExamples : r.chips,
          );
        }
        return ChatMessage(
          id: _id('a'),
          role: ChatRole.assistant,
          kind: ChatKind.answer,
          text: r.text,
          createdAt: now,
          data: r.data,
          chips: r.chips,
          refused: r.refused,
        );
    }
  }

  /// Hata balonundaki "Tekrar dene".
  Future<void> retry(ChatMessage errorMessage) async {
    final t = errorMessage.retryText;
    if (t == null) return;
    _set(
      state.copyWith(
        messages: [
          for (final m in state.messages)
            if (m.id != errorMessage.id) m,
        ],
      ),
      persist: false,
    );
    await send(t, choices: errorMessage.retryChoices, echo: false);
  }

  // ------------------------------------------------------------------ clarify

  /// Soru cevabı: tüm sorular cevaplanınca aynı komut `choices` ile yeniden gönderilir.
  Future<void> answerClarify(
    String messageId,
    String field,
    String value, {
    String? label,
  }) async {
    final m = state.messages.where((x) => x.id == messageId).firstOrNull;
    if (m == null || m.resolved || state.sending) return;
    final answers = {...m.answers, field: value};
    final done = m.questions.every((q) => answers.containsKey(q.field));
    _patchMessage(
      messageId,
      (x) => x.copyWith(answers: answers, resolved: done),
    );
    if (!done) return;
    await send(
      m.originalText ?? '',
      choices: {...m.priorChoices, ...answers},
      userBubble: label ?? value,
    );
  }

  // ------------------------------------------------------------------ kart işlemleri

  void _busy(String id, bool on) {
    final s = {...state.busyCards};
    on ? s.add(id) : s.remove(id);
    state = state.copyWith(busyCards: s);
  }

  void _cardError(String id, String? msg) {
    final e = {...state.cardErrors};
    msg == null ? e.remove(id) : e[id] = msg;
    state = state.copyWith(cardErrors: e);
  }

  /// Düzenleme formu: alanlar sunucuya PATCH edilir (yalnız `editable` alanlar).
  Future<bool> editCard(String cardId, Map<String, Object?> fields) async {
    if (state.busyCards.contains(cardId)) return false;
    _busy(cardId, true);
    _cardError(cardId, null);
    try {
      final c = await _repo.editAction(cardId, fields);
      _replaceCard(c);
      return true;
    } on Object catch (e) {
      _cardError(cardId, AppException.from(e).message);
      return false;
    } finally {
      _busy(cardId, false);
    }
  }

  Future<void> confirm(String cardId) => _decide(cardId, _repo.confirmAction);
  Future<void> reject(String cardId) => _decide(cardId, _repo.rejectAction);
  Future<void> undo(String cardId) => _decide(cardId, _repo.undoAction);

  Future<void> _decide(
    String cardId,
    Future<ActionCard> Function(String) call,
  ) async {
    if (state.busyCards.contains(cardId)) return; // çift dokunma
    _busy(cardId, true);
    _cardError(cardId, null);
    try {
      _replaceCard(await call(cardId));
    } on Object catch (e) {
      final ex = AppException.from(e);
      _cardError(cardId, ex.message);
      // 409: durum çakışması (zaten uygulandı / süresi doldu): kartı sunucudan tazele.
      if (ex.code == AppErrorCode.conflict) {
        try {
          _replaceCard(await _repo.getAction(cardId));
        } on Object {
          // Tazelenemedi; hata iletisi görünür kalır.
        }
      }
    } finally {
      _busy(cardId, false);
    }
  }

  /// Dışarıdan gelen kart (ör. öneri kabulünden dönen randevu kartı) sohbete eklenir.
  void addExternalCard(ActionCard c) {
    if (state.messages.any((m) => m.cardId == c.id)) return;
    _add(
      ChatMessage(
        id: _id('a'),
        role: ChatRole.assistant,
        kind: ChatKind.card,
        text: c.title,
        createdAt: Ist.now(),
        card: c,
        cardId: c.id,
        cardStatus: c.status.api,
      ),
    );
  }

  void dismissNotice() => state = state.copyWith(clearNotice: true);

  Future<void> clear() async {
    await ref.read(chatHistoryStoreProvider).clear(_userId);
    state = const ChatState();
  }
}

final chatControllerProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
