// Akşam kapanış sihirbazı: chip tabanlı kısa sorular (tek dokunuşla cevap), ses/klavye notu,
// önerilen kayıt değişiklikleri (onayla / geç), gün sonu özeti ve "Bugün bitti" rozeti.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/money.dart';
import '../application/closure_flow.dart';
import '../data/closure_models.dart';
import 'widgets/assistant_ui.dart';

class ClosureScreen extends ConsumerWidget {
  const ClosureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(closureProvider);
    Future<void> refresh() => ref.read(closureProvider.notifier).reload();
    return AppScaffold(
      title: 'Gün sonu',
      showMenuButton: false,
      body: async.when(
        loading: () => const SkeletonList(itemCount: 3, itemHeight: 120),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(closureProvider),
        ),
        data: (s) => ClosureBody(state: s, onRefresh: refresh),
      ),
    );
  }
}

class ClosureBody extends ConsumerStatefulWidget {
  const ClosureBody({super.key, required this.state, required this.onRefresh});
  final ClosureState state;
  final Future<void> Function() onRefresh;
  @override
  ConsumerState<ClosureBody> createState() => _ClosureBodyState();
}

class _ClosureBodyState extends ConsumerState<ClosureBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(closureFlowProvider.notifier).start(widget.state);
    });
  }

  @override
  void didUpdateWidget(covariant ClosureBody old) {
    super.didUpdateWidget(old);
    if (old.state.date != widget.state.date) {
      ref.read(closureFlowProvider.notifier).reset();
      ref.read(closureFlowProvider.notifier).start(widget.state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(closureFlowProvider);
    final s = widget.state;
    final draft = flow.draft;
    if (flow.submitted || s.isDone) {
      return _DoneView(state: s, flow: flow, onRefresh: widget.onRefresh);
    }
    if (draft == null) return const SkeletonList(itemCount: 2, itemHeight: 140);
    if (draft.atNoteStep) return _NoteStep(state: s, flow: flow);
    return _QuestionStep(
      key: ValueKey(draft.current!.id),
      state: s,
      flow: flow,
    );
  }
}

// ------------------------------------------------------------------ soru adımı

class _QuestionStep extends ConsumerStatefulWidget {
  const _QuestionStep({super.key, required this.state, required this.flow});
  final ClosureState state;
  final ClosureFlow flow;
  @override
  ConsumerState<_QuestionStep> createState() => _QuestionStepState();
}

class _QuestionStepState extends ConsumerState<_QuestionStep> {
  String? _choice; // takip ya da tutar bekleyen seçim
  final _amount = TextEditingController();
  String? _amountError;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  ClosureFlowNotifier get _n => ref.read(closureFlowProvider.notifier);

  void _tap(ClosureQuestion q, ClosureOption o) {
    if (q.needsAmount(o.value) || o.followUp.isNotEmpty) {
      setState(() {
        _choice = o.value;
        _amountError = null;
      });
      return;
    }
    _n.answer(o.value);
  }

  void _saveAmount(ClosureQuestion q) {
    final m = Money.parseUserInput(_amount.text);
    if (m == null || !m.isPositive) {
      setState(() => _amountError = 'Geçerli bir tutar girin (örn. 1.500).');
      return;
    }
    _n.answer(_choice!, amount: m);
  }

  Future<void> _addNote(ClosureQuestion q, String current) async {
    final c = TextEditingController(text: current);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not ekle'),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Kısa notunuz (klavyedeki mikrofonla da yazabilirsiniz)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    c.dispose();
    if (text != null) _n.questionNote(q.id, text);
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.flow.draft!;
    final q = draft.current!;
    final chosen = _choice == null ? null : q.option(_choice!);
    final note = draft.questionNotes[q.id] ?? '';
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        Semantics(
          label: 'Soru ${draft.index + 1} / ${draft.total}',
          child: Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: draft.total == 0 ? 0 : (draft.index) / draft.total,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
              ),
              const SizedBox(width: Space.md),
              Text(
                '${draft.index + 1} / ${draft.total}',
                style: context.text.labelLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(q.text, style: context.text.titleMedium),
              const SizedBox(height: Space.lg),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final o in q.options)
                    ChoiceChip(
                      label: Text(o.label),
                      selected: _choice == o.value,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      labelStyle: context.text.bodyLarge,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: Space.sm,
                      ),
                      onSelected: (_) => _tap(q, o),
                    ),
                ],
              ),
              if (chosen != null && chosen.followUp.isNotEmpty) ...[
                const SizedBox(height: Space.lg),
                Text('Sonrası?', style: context.text.labelLarge),
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final f in chosen.followUp)
                      ActionChip(
                        label: Text(f.label),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onPressed: () =>
                            _n.answer(chosen.value, followUp: f.value),
                      ),
                    TextButton(
                      onPressed: () => _n.answer(chosen.value),
                      child: const Text('Geç'),
                    ),
                  ],
                ),
              ],
              if (_choice != null && q.needsAmount(_choice!)) ...[
                const SizedBox(height: Space.lg),
                TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Tutar',
                    prefixText: '₺ ',
                    errorText: _amountError,
                  ),
                  onSubmitted: (_) => _saveAmount(q),
                ),
                const SizedBox(height: Space.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => _saveAmount(q),
                    child: const Text('Kaydet'),
                  ),
                ),
              ],
              if (note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.md),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.sticky_note_2_outlined,
                        size: Sizes.iconSm,
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(note, style: context.text.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            if (draft.canGoBack)
              TextButton.icon(
                onPressed: _n.back,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Geri'),
              ),
            TextButton.icon(
              onPressed: () => _addNote(q, note),
              icon: const Icon(Icons.edit_note),
              label: const Text('Not ekle'),
            ),
            const Spacer(),
            if (q.skippable)
              TextButton(
                onPressed: _n.skip,
                child: Text(widget.state.skipLabel),
              ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ not adımı

class _NoteStep extends ConsumerStatefulWidget {
  const _NoteStep({required this.state, required this.flow});
  final ClosureState state;
  final ClosureFlow flow;
  @override
  ConsumerState<_NoteStep> createState() => _NoteStepState();
}

class _NoteStepState extends ConsumerState<_NoteStep> {
  late final TextEditingController _c = TextEditingController(
    text: widget.flow.draft?.freeNote ?? '',
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final n = ref.read(closureFlowProvider.notifier);
    n.freeNote(_c.text);
    await n.submit();
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final draft = flow.draft!;
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.state.notePrompt, style: context.text.titleMedium),
              const SizedBox(height: Space.sm),
              Text(
                'Yazabilir ya da klavyenizdeki mikrofon düğmesiyle sesle yazabilirsiniz. Boş bırakabilirsiniz.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: Space.md),
              TextField(
                controller: _c,
                minLines: 3,
                maxLines: 6,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: 'Örn. Ahmet Bey\'i haftaya ara',
                ),
              ),
              if (draft.questionNotes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(
                    '${draft.questionNotes.length} soru notu da eklenecek.',
                    style: context.text.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        if (flow.error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: Semantics(
              liveRegion: true,
              child: Text(
                flow.error!,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ),
          ),
        const SizedBox(height: Space.lg),
        FilledButton.icon(
          onPressed: flow.submitting ? null : _finish,
          icon: flow.submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.check),
          label: Text(flow.error != null ? 'Tekrar dene' : 'Günü kapat'),
        ),
        if (draft.canGoBack)
          TextButton.icon(
            onPressed: flow.submitting
                ? null
                : ref.read(closureFlowProvider.notifier).back,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Geri'),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ tamamlandı

class _DoneView extends ConsumerWidget {
  const _DoneView({
    required this.state,
    required this.flow,
    required this.onRefresh,
  });
  final ClosureState state;
  final ClosureFlow flow;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = flow.result?.summary ?? state.summary;
    final proposals = flow.result?.proposals ?? state.proposals;
    return PullToRefresh(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.lg),
        children: [
          const DoneBadge(),
          const SizedBox(height: Space.md),
          if (summary != null) ClosureSummaryCard(summary: summary),
          if (proposals.isNotEmpty) ...[
            SectionLabel('Önerilen kayıt değişiklikleri'),
            for (var i = 0; i < proposals.length; i++)
              _ProposalCard(index: i, proposal: proposals[i], flow: flow),
          ],
          const SizedBox(height: Space.lg),
          OutlinedButton(
            onPressed: () => context.go(Routes.today),
            child: const Text('Bugün ekranına dön'),
          ),
        ],
      ),
    );
  }
}

/// "Bugün bitti" rozeti.
class DoneBadge extends StatelessWidget {
  const DoneBadge({super.key});
  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    return Semantics(
      label: 'Bugün bitti',
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: x.successContainer,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: x.success, size: Sizes.iconLg),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                'Bugün bitti. Elinize sağlık!',
                style: context.text.titleMedium?.copyWith(
                  color: context.colors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gün sonu özet kartı (tasarım: Özet Kartı).
class ClosureSummaryCard extends StatelessWidget {
  const ClosureSummaryCard({super.key, required this.summary});
  final ClosureSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final lines = <String>[
      if (s.appointmentsTotal > 0)
        '${s.appointmentsTotal} randevu: ${s.done} yapıldı'
            '${s.postponed > 0 ? ', ${s.postponed} ertelendi' : ''}'
            '${s.cancelled > 0 ? ', ${s.cancelled} iptal' : ''}'
            '${s.open > 0 ? ', ${s.open} sonuçsuz' : ''}',
      if (s.collected != null)
        'Tahsilat ${s.collected!.format()}, gider ${s.expense?.format() ?? '₺0,00'}',
      if (s.newRequests > 0) '${s.newRequests} yeni talep geldi',
      if (s.followups > 0) '${s.followups} takip oluşturuldu',
      if (s.tomorrowCount > 0)
        'Yarın: ${s.tomorrowCount}${s.tomorrowFirst == null ? '' : ' (ilk: ${s.tomorrowFirst})'}',
    ];
    return SectionCard(
      title: s.title,
      trailing: s.dateText.isEmpty
          ? null
          : Text(s.dateText, style: context.text.bodySmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines.isEmpty && s.text.isNotEmpty)
            Text(s.text, style: context.text.bodyMedium),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check,
                    size: Sizes.iconSm,
                    color: context.xc.success,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(l, style: context.text.bodyMedium)),
                ],
              ),
            ),
          if (s.total > 0)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                '${s.answered} cevaplandı, ${s.skipped} atlandı (${s.total} sorudan)',
                style: context.text.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProposalCard extends ConsumerWidget {
  const _ProposalCard({
    required this.index,
    required this.proposal,
    required this.flow,
  });
  final int index;
  final ClosureProposal proposal;
  final ClosureFlow flow;

  String? _route() => switch (proposal.type) {
    'payment_create' || 'expense_create' => Routes.finance,
    'offer_status' => Routes.jobs,
    'stage_update' || 'project_stage' =>
      proposal.projectId == null
          ? Routes.jobs
          : Routes.project(proposal.projectId!),
    'appointment_reschedule' => Routes.appointments,
    _ => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = flow.proposalStatus[index] ?? ProposalStatus.pending;
    final err = flow.proposalErrors[index];
    final n = ref.read(closureFlowProvider.notifier);
    if (status == ProposalStatus.skipped) return const SizedBox.shrink();
    final applied = status == ProposalStatus.applied;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: AiCard(
        kind: AiCardKind.confirm,
        title: proposal.label,
        body: [
          if (proposal.amount != null) proposal.amount!.format(),
          if (applied) 'Uygulandı.',
          if (!proposal.canApplyDirectly && !applied)
            'Eksik bilgi var; ilgili ekrandan tamamlayın.',
        ].join(' · '),
        actions: applied
            ? const []
            : [
                if (proposal.canApplyDirectly)
                  AiCardAction(
                    status == ProposalStatus.failed ? 'Tekrar dene' : 'Onayla',
                    status == ProposalStatus.applying
                        ? null
                        : () => n.applyProposal(index),
                    primary: true,
                  )
                else if (_route() != null)
                  AiCardAction(
                    'Ekranı aç',
                    () => goTo(context, _route()),
                    primary: true,
                  ),
                AiCardAction(
                  'Geç',
                  status == ProposalStatus.applying
                      ? null
                      : () => n.skipProposal(index),
                ),
              ],
        child: err == null
            ? (status == ProposalStatus.applying
                  ? const LinearProgressIndicator()
                  : null)
            : Text(
                err,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.error,
                ),
              ),
      ),
    );
  }
}
