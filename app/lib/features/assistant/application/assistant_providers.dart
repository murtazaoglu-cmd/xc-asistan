// Brifing, müdür, kutu, tercih ve öneri sağlayıcıları. Otomatik yeniden deneme KAPALI:
// hata ekranı "Tekrar dene" ile çalışır.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/assistant_repository.dart';
import '../data/briefing_models.dart';
import '../data/import_models.dart';
import '../data/inbox_models.dart';
import '../data/insight_models.dart';
import 'notification_scheduler.dart';

Duration? noRetry(int retryCount, Object error) => null;

// ------------------------------------------------------------------ brifing

final briefingTodayProvider = FutureProvider.autoDispose<Briefing>(
  (ref) => ref.watch(assistantRepositoryProvider).briefingToday(),
  retry: noRetry,
);

/// `type`: morning | weekly | monthly | evening | null (tümü).
final briefingHistoryProvider = FutureProvider.autoDispose
    .family<List<Briefing>, String?>(
      (ref, type) => ref
          .watch(assistantRepositoryProvider)
          .briefings(type: type, limit: 30),
      retry: noRetry,
    );

// ------------------------------------------------------------------ müdür

class InsightStatusFilter extends Notifier<String> {
  @override
  String build() => 'acik';
  void set(String v) => state = v;
}

final insightStatusFilterProvider =
    NotifierProvider<InsightStatusFilter, String>(InsightStatusFilter.new);

class InsightsNotifier extends AsyncNotifier<List<Insight>> {
  @override
  Future<List<Insight>> build() async {
    final status = ref.watch(insightStatusFilterProvider);
    return ref.read(assistantRepositoryProvider).insights(status: status);
  }

  AssistantRepository get _repo => ref.read(assistantRepositoryProvider);

  void _remove(String id) {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData([
      for (final i in cur)
        if (i.id != id) i,
    ]);
  }

  Future<void> snooze(String id, int days) async {
    await _repo.snoozeInsight(id, days);
    _remove(id);
  }

  Future<void> dismiss(String id) async {
    await _repo.dismissInsight(id);
    _remove(id);
  }

  Future<void> markApplied(String id) async {
    await _repo.markInsightApplied(id);
    _remove(id);
  }

  /// `yararli` açık kalır (işaretlenir); `yanlis`/`alakasiz` kapanır.
  Future<void> feedback(String id, String verdict, {String? note}) async {
    await _repo.insightFeedback(id, verdict, note: note);
    if (verdict == 'yararli') {
      final cur = state.value;
      if (cur != null) {
        state = AsyncData([
          for (final i in cur) i.id == id ? i.withFeedback(verdict) : i,
        ]);
      }
    } else {
      _remove(id);
    }
  }

  Future<void> refreshFromServer() async {
    state = const AsyncLoading<List<Insight>>();
    state = await AsyncValue.guard(
      () => _repo.insights(status: ref.read(insightStatusFilterProvider)),
    );
  }
}

final insightsProvider =
    AsyncNotifierProvider.autoDispose<InsightsNotifier, List<Insight>>(
      InsightsNotifier.new,
      retry: noRetry,
    );

class InsightRulesNotifier extends AsyncNotifier<InsightRulesConfig> {
  @override
  Future<InsightRulesConfig> build() =>
      ref.read(assistantRepositoryProvider).insightRules();

  Future<void> setEnabled(String key, bool enabled) async {
    final cfg = await ref
        .read(assistantRepositoryProvider)
        .updateInsightRules(
          rules: [(key: key, enabled: enabled, params: null)],
        );
    state = AsyncData(cfg);
  }

  Future<void> setParams(String key, Map<String, int> params) async {
    final cfg = await ref
        .read(assistantRepositoryProvider)
        .updateInsightRules(rules: [(key: key, enabled: null, params: params)]);
    state = AsyncData(cfg);
  }

  Future<void> setCalibration(bool on) async {
    final cfg = await ref
        .read(assistantRepositoryProvider)
        .updateInsightRules(calibrationMode: on);
    state = AsyncData(cfg);
  }
}

final insightRulesProvider =
    AsyncNotifierProvider.autoDispose<InsightRulesNotifier, InsightRulesConfig>(
      InsightRulesNotifier.new,
      retry: noRetry,
    );

// ------------------------------------------------------------------ bildirim kutusu

class InboxState {
  const InboxState({
    required this.items,
    required this.unreadCount,
    this.nextBefore,
    this.loadingMore = false,
    this.loadMoreError,
  });
  final List<InboxItem> items;
  final int unreadCount;
  final String? nextBefore;
  final bool loadingMore;
  final String? loadMoreError;
  bool get hasMore => nextBefore != null;

  InboxState copyWith({
    List<InboxItem>? items,
    int? unreadCount,
    String? nextBefore,
    bool clearNext = false,
    bool? loadingMore,
    String? loadMoreError,
    bool clearError = false,
  }) => InboxState(
    items: items ?? this.items,
    unreadCount: unreadCount ?? this.unreadCount,
    nextBefore: clearNext ? null : (nextBefore ?? this.nextBefore),
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
  );
}

class InboxUnreadOnly extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final inboxUnreadOnlyProvider = NotifierProvider<InboxUnreadOnly, bool>(
  InboxUnreadOnly.new,
);

/// Üst çubuk zil rozeti: okunmamış sayısı. Hata/çevrimdışı → 0 (sessiz).
final inboxUnreadCountProvider = FutureProvider<int>((ref) async {
  try {
    return await ref.watch(assistantRepositoryProvider).inboxUnreadCount();
  } on Object {
    return 0;
  }
});

class InboxNotifier extends AsyncNotifier<InboxState> {
  AssistantRepository get _repo => ref.read(assistantRepositoryProvider);

  @override
  Future<InboxState> build() async {
    final only = ref.watch(inboxUnreadOnlyProvider);
    final p = await _repo.inbox(unreadOnly: only);
    return InboxState(
      items: p.items,
      unreadCount: p.unreadCount,
      nextBefore: p.nextBefore,
    );
  }

  Future<void> loadMore() async {
    final cur = state.value;
    if (cur == null || !cur.hasMore || cur.loadingMore) return;
    state = AsyncData(cur.copyWith(loadingMore: true, clearError: true));
    try {
      final p = await _repo.inbox(
        unreadOnly: ref.read(inboxUnreadOnlyProvider),
        before: cur.nextBefore,
      );
      state = AsyncData(
        cur.copyWith(
          items: [...cur.items, ...p.items],
          unreadCount: p.unreadCount,
          nextBefore: p.nextBefore,
          clearNext: p.nextBefore == null,
          loadingMore: false,
        ),
      );
    } on Object catch (e) {
      state = AsyncData(cur.copyWith(loadingMore: false, loadMoreError: '$e'));
    }
  }

  /// Öğeyi okundu + ack işaretler (iyimser; hata sessiz).
  Future<void> open(InboxItem item) async {
    final cur = state.value;
    if (cur != null && !item.isRead) {
      final now = DateTime.now().toUtc();
      state = AsyncData(
        cur.copyWith(
          items: [
            for (final i in cur.items)
              i.id == item.id ? i.copyWith(readAt: now) : i,
          ],
          unreadCount: (cur.unreadCount - 1).clamp(0, 1 << 30),
        ),
      );
    }
    try {
      await _repo.ackInbox(item.id);
    } on Object {
      // Kutu bilgisi kritik değil.
    }
    ref.invalidate(inboxUnreadCountProvider);
  }

  Future<void> markAllRead() async {
    await _repo.markAllInboxRead();
    final cur = state.value;
    if (cur != null) {
      final now = DateTime.now().toUtc();
      state = AsyncData(
        cur.copyWith(
          items: [
            for (final i in cur.items) i.isRead ? i : i.copyWith(readAt: now),
          ],
          unreadCount: 0,
        ),
      );
    }
    ref.invalidate(inboxUnreadCountProvider);
  }
}

final inboxProvider =
    AsyncNotifierProvider.autoDispose<InboxNotifier, InboxState>(
      InboxNotifier.new,
      retry: noRetry,
    );

// ------------------------------------------------------------------ tercihler

class PrefsNotifier extends AsyncNotifier<AssistantPrefs> {
  @override
  Future<AssistantPrefs> build() =>
      ref.read(assistantRepositoryProvider).prefs();

  /// Kısmi güncelleme. Başarısızsa önceki değer korunur ve hata yeniden fırlatılır.
  Future<void> save(Map<String, Object?> patch) async {
    final prev = state.value;
    final next = await ref.read(assistantRepositoryProvider).updatePrefs(patch);
    state = AsyncData(next);
    if (prev != null) {
      // Yerel bildirimleri yeni saatlere göre yeniden kur (hata sessiz).
      try {
        await ref.read(assistantNotificationSchedulerProvider).apply();
      } on Object {
        // Bildirim kurulamadı; tercih yine de kaydedildi.
      }
    }
  }
}

final assistantPrefsProvider =
    AsyncNotifierProvider.autoDispose<PrefsNotifier, AssistantPrefs>(
      PrefsNotifier.new,
      retry: noRetry,
    );

// ------------------------------------------------------------------ öneriler / yazışma

typedef SuggestionQuery = ({String? conversationId, String? customerKey});

class SuggestionsNotifier extends AsyncNotifier<List<Suggestion>> {
  SuggestionsNotifier(this.query);
  final SuggestionQuery query;

  AssistantRepository get _repo => ref.read(assistantRepositoryProvider);

  @override
  Future<List<Suggestion>> build() => _repo.suggestions(
    conversationId: query.conversationId,
    customerKey: query.customerKey,
  );

  /// Karar ver; bekleyenler listeden çıkar. `randevu` kabulünde dönen onay kartı yanıtla birlikte verilir.
  Future<SuggestionDecision> decide(
    String id,
    String status, {
    Map<String, String>? fields,
  }) async {
    final d = await _repo.decideSuggestion(id, status, fields: fields);
    final cur = state.value;
    if (cur != null)
      state = AsyncData([
        for (final s in cur)
          if (s.id != id) s,
      ]);
    return d;
  }
}

final suggestionsProvider = AsyncNotifierProvider.autoDispose
    .family<SuggestionsNotifier, List<Suggestion>, SuggestionQuery>(
      SuggestionsNotifier.new,
      retry: noRetry,
    );

class ConversationsNotifier extends AsyncNotifier<List<ConversationRef>> {
  ConversationsNotifier(this.customerKey);
  final String customerKey;

  @override
  Future<List<ConversationRef>> build() => ref
      .read(assistantRepositoryProvider)
      .conversations(customerKey: customerKey);

  Future<void> delete(String id) async {
    await ref.read(assistantRepositoryProvider).deleteConversation(id);
    final cur = state.value;
    if (cur != null)
      state = AsyncData([
        for (final c in cur)
          if (c.id != id) c,
      ]);
  }
}

final conversationsProvider = AsyncNotifierProvider.autoDispose
    .family<ConversationsNotifier, List<ConversationRef>, String>(
      ConversationsNotifier.new,
      retry: noRetry,
    );

final customerNotesProvider = FutureProvider.autoDispose
    .family<List<AssistantNote>, String>(
      (ref, key) => ref.watch(assistantRepositoryProvider).customerNotes(key),
      retry: noRetry,
    );

final consentsProvider = FutureProvider.autoDispose<List<ConsentRecord>>(
  (ref) => ref.watch(assistantRepositoryProvider).consents(),
  retry: noRetry,
);
