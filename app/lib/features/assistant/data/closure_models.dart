// Akşam kapanışı modelleri (sözleşme A2 §2).
import 'package:flutter/foundation.dart';

import '../../../core/util/json.dart';
import '../../../core/util/money.dart';
import 'command_models.dart';
import 'model_utils.dart';

@immutable
class ClosureOption {
  const ClosureOption({
    required this.value,
    required this.label,
    this.followUp = const [],
  });
  final String value;
  final String label;
  final List<ChoiceOption> followUp;

  factory ClosureOption.fromJson(JsonMap j) => ClosureOption(
    value: j.strOr('value'),
    label: j.strOrNull('label') ?? j.strOr('value'),
    followUp: ChoiceOption.list(j['follow_up']),
  );
}

@immutable
class ClosureQuestion {
  const ClosureQuestion({
    required this.id,
    required this.kind,
    required this.text,
    this.options = const [],
    this.skippable = true,
    this.context = const {},
    this.answer,
  });
  final String id;

  /// appointment | money | stage | cost | tomorrow | ...
  final String kind;
  final String text;
  final List<ClosureOption> options;
  final bool skippable;
  final JsonMap context;

  /// Daha önce verilmiş yanıt (varsa).
  final Object? answer;

  bool get isMoney => kind == 'money';
  bool get answered => answer != null;

  /// Tutar isteyen seçenekler (para sorusunda "tahsilat"/"gider").
  bool needsAmount(String choice) =>
      isMoney && (choice == 'tahsilat' || choice == 'gider');

  ClosureOption? option(String value) {
    for (final o in options) {
      if (o.value == value) return o;
    }
    return null;
  }

  String get projectId => context.strOr('project_id');

  factory ClosureQuestion.fromJson(JsonMap j) => ClosureQuestion(
    id: j.strOr('id'),
    kind: j.strOr('kind'),
    text: j.strOr('text'),
    options: [for (final o in j.list('options')) ClosureOption.fromJson(o)],
    skippable: j.boolOr('skippable', true),
    context: j.mapOrNull('context') ?? const {},
    answer: j['answer'],
  );
}

@immutable
class ClosureSummary {
  const ClosureSummary({
    required this.title,
    required this.dateText,
    required this.text,
    this.appointmentsTotal = 0,
    this.done = 0,
    this.postponed = 0,
    this.cancelled = 0,
    this.open = 0,
    this.collected,
    this.expense,
    this.newRequests = 0,
    this.followups = 0,
    this.tomorrowCount = 0,
    this.tomorrowFirst,
    this.answered = 0,
    this.skipped = 0,
    this.total = 0,
    this.percent = 0,
  });
  final String title;
  final String dateText;
  final String text;
  final int appointmentsTotal;
  final int done;
  final int postponed;
  final int cancelled;
  final int open;

  /// Saha rolünde null (finans verisi yok).
  final Money? collected;
  final Money? expense;
  final int newRequests;
  final int followups;
  final int tomorrowCount;
  final String? tomorrowFirst;
  final int answered;
  final int skipped;
  final int total;
  final int percent;

  factory ClosureSummary.fromJson(JsonMap j) {
    final a = j.mapOrNull('appointments') ?? const <String, dynamic>{};
    final m = j.mapOrNull('money');
    final t = j.mapOrNull('tomorrow') ?? const <String, dynamic>{};
    final c = j.mapOrNull('completion') ?? const <String, dynamic>{};
    return ClosureSummary(
      title: j.strOr('title', 'Gün sonu özeti'),
      dateText: j.strOr('date_text'),
      text: j.strOr('text'),
      appointmentsTotal: a.intOr('total'),
      done: a.intOr('done'),
      postponed: a.intOr('postponed'),
      cancelled: a.intOr('cancelled'),
      open: a.intOr('open'),
      collected: m == null ? null : kurus(m, 'collected_kurus'),
      expense: m == null ? null : kurus(m, 'expense_kurus'),
      newRequests: j.intOr('new_requests_today'),
      followups: j.intOr('followups_created'),
      tomorrowCount: t.intOr('count'),
      tomorrowFirst: t.strOrNull('first'),
      answered: c.intOr('answered'),
      skipped: c.intOr('skipped'),
      total: c.intOr('total'),
      percent: c.intOr('percent'),
    );
  }
}

/// Sunucunun önerdiği kayıt değişikliği (kullanıcı onayıyla uygulanır).
@immutable
class ClosureProposal {
  const ClosureProposal({
    required this.type,
    required this.label,
    required this.method,
    required this.path,
    required this.body,
    this.questionId,
    this.amount,
    this.projectId,
    this.needs = const [],
  });
  final String type;
  final String label;
  final String? questionId;
  final Money? amount;
  final String? projectId;
  final String method;
  final String path;
  final JsonMap body;

  /// İstemcinin tamamlaması gereken alanlar.
  final List<String> needs;

  /// Eksiksiz mi: doğrudan uygulanabilir.
  bool get canApplyDirectly =>
      method.isNotEmpty &&
      path.isNotEmpty &&
      needs.isEmpty &&
      !hasPlaceholder(path);

  factory ClosureProposal.fromJson(JsonMap j) {
    final apply = j.mapOrNull('apply') ?? const <String, dynamic>{};
    return ClosureProposal(
      type: j.strOr('type'),
      label: j.strOrNull('label') ?? j.strOr('type'),
      questionId: j.strOrNull('question_id'),
      amount: kurusOrNull(j, 'amount_kurus'),
      projectId: j.strOrNull('project_id'),
      method: apply.strOr('method').toUpperCase(),
      path: apply.strOr('path'),
      body: apply.mapOrNull('body') ?? const {},
      needs: apply.stringList('needs'),
    );
  }
}

enum ClosureStatus { pending, partial, done, skipped }

@immutable
class ClosureState {
  const ClosureState({
    required this.date,
    required this.status,
    this.completeness = 0,
    this.questions = const [],
    this.freeNote,
    this.notePrompt = 'Not düşmek istediğiniz bir şey var mı?',
    this.skipLabel = 'Atla',
    this.summary,
    this.proposals = const [],
    this.closedAt,
  });
  final String date;
  final ClosureStatus status;
  final int completeness;
  final List<ClosureQuestion> questions;
  final String? freeNote;
  final String notePrompt;
  final String skipLabel;
  final ClosureSummary? summary;
  final List<ClosureProposal> proposals;
  final DateTime? closedAt;

  /// "Bugün bitti" rozeti.
  bool get isDone => status == ClosureStatus.done;

  static ClosureStatus _status(String? v) => switch (v) {
    'done' => ClosureStatus.done,
    'partial' => ClosureStatus.partial,
    'skipped' => ClosureStatus.skipped,
    _ => ClosureStatus.pending,
  };

  factory ClosureState.fromJson(JsonMap j) {
    final s = j.mapOrNull('summary_card');
    return ClosureState(
      date: j.strOr('date'),
      status: _status(j.str('status')),
      completeness: j.intOr('completeness'),
      questions: [
        for (final q in j.list('questions')) ClosureQuestion.fromJson(q),
      ],
      freeNote: j.strOrNull('free_note'),
      notePrompt:
          j.strOrNull('note_prompt') ??
          'Not düşmek istediğiniz bir şey var mı?',
      skipLabel: j.strOrNull('skip_label') ?? 'Atla',
      summary: s == null ? null : ClosureSummary.fromJson(s),
      proposals: [
        for (final p in j.list('closure_proposals'))
          ClosureProposal.fromJson(p),
      ],
      closedAt: j.dateTime('closed_at'),
    );
  }
}

/// `POST /closure/answers` gövdesindeki tek yanıt.
@immutable
class ClosureAnswer {
  const ClosureAnswer({
    required this.questionId,
    this.choice,
    this.followUp,
    this.amount,
    this.projectId,
    this.skipped = false,
  });
  final String questionId;
  final String? choice;
  final String? followUp;
  final Money? amount;
  final String? projectId;
  final bool skipped;

  JsonMap toJson() => {
    'question_id': questionId,
    if (skipped) 'skipped': true,
    if (!skipped && choice != null) 'choice': choice,
    if (!skipped && followUp != null) 'follow_up': followUp,
    if (!skipped && amount != null) 'amount_kurus': amount!.kurus,
    if (!skipped && projectId != null && projectId!.isNotEmpty)
      'project_id': projectId,
  };
}

@immutable
class ClosureResult {
  const ClosureResult({
    required this.applied,
    required this.proposals,
    this.state,
    this.summary,
  });
  final List<JsonMap> applied;
  final List<ClosureProposal> proposals;
  final ClosureState? state;
  final ClosureSummary? summary;

  factory ClosureResult.fromJson(JsonMap j) {
    final log = j.mapOrNull('log');
    final sc = j.mapOrNull('summary_card');
    return ClosureResult(
      applied: j.list('applied'),
      proposals: [
        for (final p in j.list('closure_proposals'))
          ClosureProposal.fromJson(p),
      ],
      state: log == null ? null : ClosureState.fromJson(log),
      summary: sc == null ? null : ClosureSummary.fromJson(sc),
    );
  }
}
