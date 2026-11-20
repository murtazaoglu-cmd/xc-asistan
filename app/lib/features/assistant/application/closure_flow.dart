// Akşam kapanış sihirbazı: saf mantık ([ClosureDraft]) + durum yönetimi ([ClosureFlowNotifier]).
// Kısa, tek dokunuşlu cevaplar; her soru atlanabilir; tutar yalnız para sorusunda.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/util/money.dart';
import '../data/assistant_repository.dart';
import '../data/closure_models.dart';
import 'assistant_providers.dart';

/// Sihirbazın o ana kadarki cevapları (değişmez). Yalnız henüz cevaplanmamış sorular sorulur.
@immutable
class ClosureDraft {
  const ClosureDraft({
    required this.questions,
    this.answers = const {},
    this.questionNotes = const {},
    this.freeNote = '',
    this.index = 0,
  });

  factory ClosureDraft.from(ClosureState s) => ClosureDraft(
    questions: [
      for (final q in s.questions)
        if (!q.answered) q,
    ],
    freeNote: s.freeNote ?? '',
  );

  final List<ClosureQuestion> questions;
  final Map<String, ClosureAnswer> answers;

  /// Soru başına "Not ekle" metinleri.
  final Map<String, String> questionNotes;
  final String freeNote;
  final int index;

  ClosureQuestion? get current =>
      index < questions.length ? questions[index] : null;

  /// Sorular bitti, serbest not adımı.
  bool get atNoteStep => index >= questions.length;
  int get total => questions.length;
  bool get canGoBack => index > 0;

  ClosureAnswer? answerFor(String questionId) => answers[questionId];

  ClosureDraft _copy({
    Map<String, ClosureAnswer>? answers,
    Map<String, String>? questionNotes,
    String? freeNote,
    int? index,
  }) => ClosureDraft(
    questions: questions,
    answers: answers ?? this.answers,
    questionNotes: questionNotes ?? this.questionNotes,
    freeNote: freeNote ?? this.freeNote,
    index: index ?? this.index,
  );

  /// Mevcut soruyu cevaplar ve ilerler. Para sorusunda "tahsilat/gider" için pozitif [amount] şarttır.
  ClosureDraft answer(
    String choice, {
    String? followUp,
    Money? amount,
    String? projectId,
  }) {
    final q = current;
    if (q == null) return this;
    if (q.needsAmount(choice) && (amount == null || !amount.isPositive)) {
      throw ArgumentError('Tutar girilmeli.');
    }
    final a = ClosureAnswer(
      questionId: q.id,
      choice: choice,
      followUp: followUp,
      amount: q.needsAmount(choice) ? amount : null,
      projectId: q.needsAmount(choice)
          ? (projectId ?? (q.projectId.isEmpty ? null : q.projectId))
          : null,
    );
    return _copy(answers: {...answers, q.id: a}, index: index + 1);
  }

  ClosureDraft skip() {
    final q = current;
    if (q == null) return this;
    return _copy(
      answers: {
        ...answers,
        q.id: ClosureAnswer(questionId: q.id, skipped: true),
      },
      index: index + 1,
    );
  }

  ClosureDraft back() => canGoBack ? _copy(index: index - 1) : this;

  ClosureDraft withQuestionNote(String questionId, String note) {
    final n = {...questionNotes};
    note.trim().isEmpty ? n.remove(questionId) : n[questionId] = note.trim();
    return _copy(questionNotes: n);
  }

  ClosureDraft withFreeNote(String note) => _copy(freeNote: note);

  /// Sunucuya gidecek cevaplar (soru sırasıyla).
  List<ClosureAnswer> get payload => [
    for (final q in questions)
      if (answers[q.id] != null) answers[q.id]!,
  ];

  int get answeredCount => answers.values.where((a) => !a.skipped).length;
  int get skippedCount => answers.values.where((a) => a.skipped).length;

  /// Serbest not + soru notları tek metinde ("Ahmet Yılmaz: ..." biçimi).
  String? get noteText {
    final parts = <String>[
      if (freeNote.trim().isNotEmpty) freeNote.trim(),
      for (final q in questions)
        if (questionNotes[q.id] != null) '${_label(q)}: ${questionNotes[q.id]}',
    ];
    final s = parts.join('\n');
    return s.isEmpty ? null : s;
  }

  static String _label(ClosureQuestion q) {
    final c = q.context['customer_name'];
    return c is String && c.isNotEmpty ? c : q.text;
  }
}

enum ProposalStatus { pending, applying, applied, skipped, failed }

@immutable
class ClosureFlow {
  const ClosureFlow({
    this.draft,
    this.date,
    this.submitting = false,
    this.result,
    this.error,
    this.proposalStatus = const {},
    this.proposalErrors = const {},
  });
  final ClosureDraft? draft;
  final String? date;
  final bool submitting;
  final ClosureResult? result;
  final String? error;
  final Map<int, ProposalStatus> proposalStatus;
  final Map<int, String> proposalErrors;

  bool get submitted => result != null;

  ClosureFlow copyWith({
    ClosureDraft? draft,
    String? date,
    bool? submitting,
    ClosureResult? result,
    String? error,
    bool clearError = false,
    Map<int, ProposalStatus>? proposalStatus,
    Map<int, String>? proposalErrors,
  }) => ClosureFlow(
    draft: draft ?? this.draft,
    date: date ?? this.date,
    submitting: submitting ?? this.submitting,
    result: result ?? this.result,
    error: clearError ? null : (error ?? this.error),
    proposalStatus: proposalStatus ?? this.proposalStatus,
    proposalErrors: proposalErrors ?? this.proposalErrors,
  );
}

class ClosureNotifier extends AsyncNotifier<ClosureState> {
  @override
  Future<ClosureState> build() =>
      ref.read(assistantRepositoryProvider).closureToday();

  Future<void> reload() async {
    state = const AsyncLoading<ClosureState>();
    state = await AsyncValue.guard(
      () => ref.read(assistantRepositoryProvider).closureToday(refresh: true),
    );
  }
}

final closureProvider =
    AsyncNotifierProvider.autoDispose<ClosureNotifier, ClosureState>(
      ClosureNotifier.new,
      retry: noRetry,
    );

class ClosureFlowNotifier extends Notifier<ClosureFlow> {
  @override
  ClosureFlow build() => const ClosureFlow();

  AssistantRepository get _repo => ref.read(assistantRepositoryProvider);

  /// Sunucu durumuyla sihirbazı başlatır (aynı gün için bir kez).
  void start(ClosureState s) {
    if (state.draft != null && state.date == s.date) return;
    state = ClosureFlow(draft: ClosureDraft.from(s), date: s.date);
  }

  void _draft(ClosureDraft Function(ClosureDraft) f) {
    final d = state.draft;
    if (d == null) return;
    state = state.copyWith(draft: f(d), clearError: true);
  }

  void answer(
    String choice, {
    String? followUp,
    Money? amount,
    String? projectId,
  }) => _draft(
    (d) => d.answer(
      choice,
      followUp: followUp,
      amount: amount,
      projectId: projectId,
    ),
  );
  void skip() => _draft((d) => d.skip());
  void back() => _draft((d) => d.back());
  void questionNote(String qid, String note) =>
      _draft((d) => d.withQuestionNote(qid, note));
  void freeNote(String note) => _draft((d) => d.withFreeNote(note));

  /// Cevapları gönderir ve günü kapatır (`finish: true`).
  Future<bool> submit({bool finish = true}) async {
    final d = state.draft;
    final date = state.date;
    if (d == null || date == null || state.submitting) return false;
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final r = await _repo.submitClosure(
        date: date,
        answers: d.payload,
        freeNote: d.noteText,
        finish: finish,
      );
      state = state.copyWith(
        submitting: false,
        result: r,
        proposalStatus: {
          for (var i = 0; i < r.proposals.length; i++)
            i: ProposalStatus.pending,
        },
      );
      ref.invalidate(closureProvider);
      return true;
    } on Object catch (e) {
      state = state.copyWith(
        submitting: false,
        error: AppException.from(e).message,
      );
      return false;
    }
  }

  void _setProposal(int i, ProposalStatus s, {String? error}) {
    final errs = {...state.proposalErrors};
    error == null ? errs.remove(i) : errs[i] = error;
    state = state.copyWith(
      proposalStatus: {...state.proposalStatus, i: s},
      proposalErrors: errs,
    );
  }

  void skipProposal(int i) => _setProposal(i, ProposalStatus.skipped);

  /// Önerilen kayıt değişikliğini uygular (yalnız eksiksiz tarifler).
  Future<void> applyProposal(int i) async {
    final r = state.result;
    if (r == null || i >= r.proposals.length) return;
    final p = r.proposals[i];
    if (!p.canApplyDirectly ||
        state.proposalStatus[i] == ProposalStatus.applying)
      return;
    _setProposal(i, ProposalStatus.applying);
    try {
      await _repo.callApply(p.method, p.path, p.body);
      _setProposal(i, ProposalStatus.applied);
    } on Object catch (e) {
      _setProposal(
        i,
        ProposalStatus.failed,
        error: AppException.from(e).message,
      );
    }
  }

  void reset() => state = const ClosureFlow();
}

final closureFlowProvider =
    NotifierProvider.autoDispose<ClosureFlowNotifier, ClosureFlow>(
      ClosureFlowNotifier.new,
    );
