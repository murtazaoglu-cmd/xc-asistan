// Müdür önerisi kartı: etiket (Uyarı/Fırsat/Bilgi), başlık, "Neden?" (sayısal dayanak), aksiyonlar,
// Sonra (1 gün / 3 gün / 1 hafta), Yaptım, Kapat, geri bildirim (yararlı / yararlı değil).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/tokens.dart';
import '../../application/assistant_providers.dart';
import '../../data/insight_models.dart';
import 'assistant_ui.dart';
import 'insight_actions.dart';

class InsightCardView extends ConsumerStatefulWidget {
  const InsightCardView({super.key, required this.insight});
  final Insight insight;

  @override
  ConsumerState<InsightCardView> createState() => _InsightCardViewState();
}

class _InsightCardViewState extends ConsumerState<InsightCardView> {
  bool _why = false;
  bool _busy = false;

  Future<void> _run(Future<void> Function() f, {String? okMessage}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
      if (mounted && okMessage != null) toast(context, okMessage);
    } on Object catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _negativeFeedback() async {
    final verdict = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Bu öneri neden yararlı değil?')),
            ListTile(
              leading: const Icon(Icons.rule),
              title: const Text('Yanlış (sayılar ya da durum doğru değil)'),
              onTap: () => Navigator.pop(ctx, 'yanlis'),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Alakasız (bana gerekmiyor)'),
              onTap: () => Navigator.pop(ctx, 'alakasiz'),
            ),
          ],
        ),
      ),
    );
    if (verdict == null) return;
    await _run(
      () => ref
          .read(insightsProvider.notifier)
          .feedback(widget.insight.id, verdict),
      okMessage: 'Teşekkürler; öneri kapatıldı.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.insight;
    final x = context.xc;
    final open = i.isOpen;
    final notifier = ref.read(insightsProvider.notifier);
    return Semantics(
      container: true,
      label: 'Müdür önerisi: ${i.title}',
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: x.aiContainer,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: x.ai.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, size: Sizes.iconSm, color: x.ai),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Müdür önerisi',
                    style: context.text.labelLarge?.copyWith(
                      color: x.onAiContainer,
                    ),
                  ),
                ),
                InsightTagChip(
                  tag: i.tag,
                  critical: i.severity == InsightSeverity.critical,
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(
              i.title,
              style: context.text.titleMedium?.copyWith(color: x.onAiContainer),
            ),
            if (i.body.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Text(
                i.body,
                style: context.text.bodyMedium?.copyWith(
                  color: x.onAiContainer,
                ),
              ),
            ],
            if (!open)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  i.status == 'ertelendi'
                      ? 'Ertelendi'
                      : (i.status == 'uygulandi' ? 'Yapıldı' : 'Kapatıldı'),
                  style: context.text.labelMedium?.copyWith(
                    color: x.onAiContainer,
                  ),
                ),
              ),
            if (!i.evidence.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _why = !_why),
                  child: Text(_why ? 'Gizle' : 'Neden?'),
                ),
              ),
            if (_why) _Evidence(evidence: i.evidence),
            if (open && i.actions.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (var n = 0; n < i.actions.length; n++)
                    n == 0
                        ? FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: x.ai,
                              foregroundColor: x.onAi,
                            ),
                            onPressed: _busy
                                ? null
                                : () => runInsightAction(
                                    context,
                                    ref,
                                    i,
                                    i.actions[n],
                                  ),
                            icon: Icon(
                              insightActionIcon(i.actions[n].type),
                              size: 18,
                            ),
                            label: Text(i.actions[n].label),
                          )
                        : OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => runInsightAction(
                                    context,
                                    ref,
                                    i,
                                    i.actions[n],
                                  ),
                            icon: Icon(
                              insightActionIcon(i.actions[n].type),
                              size: 18,
                            ),
                            label: Text(i.actions[n].label),
                          ),
                ],
              ),
            ],
            if (open) ...[
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PopupMenuButton<int>(
                    tooltip: 'Sonra hatırlat',
                    enabled: !_busy,
                    onSelected: (days) => _run(
                      () => notifier.snooze(i.id, days),
                      okMessage: 'Ertelendi.',
                    ),
                    itemBuilder: (_) => [
                      for (final c in snoozeChoices)
                        PopupMenuItem(
                          value: c.days,
                          height: Sizes.minTouch,
                          child: Text(c.label),
                        ),
                    ],
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: Sizes.minTouch,
                        minWidth: Sizes.minTouch,
                      ),
                      child: Center(
                        widthFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.md,
                          ),
                          child: Text(
                            'Sonra ▾',
                            style: context.text.labelLarge?.copyWith(
                              color: x.ai,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => notifier.markApplied(i.id),
                            okMessage: 'Yapıldı olarak işaretlendi.',
                          ),
                    child: const Text('Yaptım'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => notifier.dismiss(i.id),
                            okMessage: 'Kapatıldı.',
                          ),
                    child: const Text('Kapat'),
                  ),
                  IconButton(
                    tooltip: 'Yararlı',
                    onPressed: _busy || i.feedback == 'yararli'
                        ? null
                        : () => _run(
                            () => notifier.feedback(i.id, 'yararli'),
                            okMessage: 'Teşekkürler.',
                          ),
                    icon: Icon(
                      i.feedback == 'yararli'
                          ? Icons.thumb_up
                          : Icons.thumb_up_outlined,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Yararlı değil',
                    onPressed: _busy ? null : _negativeFeedback,
                    icon: const Icon(Icons.thumb_down_outlined),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Evidence extends StatelessWidget {
  const _Evidence({required this.evidence});
  final InsightEvidence evidence;
  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: context.colors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (evidence.why != null)
            Text(evidence.why!, style: context.text.bodySmall),
          for (final m in evidence.metrics)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(m.label, style: context.text.bodyMedium),
                  ),
                  Text(
                    m.display,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: x.onAiContainer,
                    ),
                  ),
                ],
              ),
            ),
          for (final r in evidence.refs)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text('• ${r.label}', style: context.text.bodySmall),
            ),
        ],
      ),
    );
  }
}
