import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// Asistan/yapay zekâ kartı türleri (tasarım: Onay kartı, Not önerisi, Taslak yanıt,
/// Müdür önerisi, Özet kartı). Hepsi aynı iskeleti kullanır: etiket, başlık, gövde, eylemler.
enum AiCardKind { summary, confirm, noteSuggestion, draftReply, managerTip }

class AiCardAction {
  const AiCardAction(this.label, this.onPressed, {this.primary = false});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
}

/// Açık mor zeminli asistan kartı. Renk yalnız anlam taşımaz: her tür ikon + etiket de taşır.
class AiCard extends StatelessWidget {
  const AiCard({
    super.key,
    required this.kind,
    required this.title,
    this.body,
    this.actions = const [],
    this.onWhy,
    this.child,
  });

  final AiCardKind kind;
  final String title;
  final String? body;
  final List<AiCardAction> actions;

  /// "Neden?" bağlantısı (öneri gerekçesini açar). Yoksa gösterilmez.
  final VoidCallback? onWhy;

  /// Gövdenin altına ek içerik (ör. taslak yanıt metni).
  final Widget? child;

  static (IconData, String) _meta(AiCardKind k) => switch (k) {
    AiCardKind.summary => (Icons.auto_awesome, 'Asistan Özeti'),
    AiCardKind.confirm => (Icons.fact_check_outlined, 'Onay'),
    AiCardKind.noteSuggestion => (Icons.sticky_note_2_outlined, 'Not önerisi'),
    AiCardKind.draftReply => (Icons.edit_note, 'Taslak yanıt'),
    AiCardKind.managerTip => (Icons.warning_amber_rounded, 'Müdür önerisi'),
  };

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    final (icon, tag) = _meta(kind);
    final warn = kind == AiCardKind.managerTip;
    return Semantics(
      container: true,
      label: '$tag: $title',
      child: Container(
        width: double.infinity,
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
                Icon(icon, size: Sizes.iconSm, color: x.ai),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    tag,
                    style: context.text.labelLarge?.copyWith(
                      color: x.onAiContainer,
                    ),
                  ),
                ),
                if (warn)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.sm,
                      vertical: Space.xs,
                    ),
                    decoration: BoxDecoration(
                      color: x.warningContainer,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      'Uyarı',
                      style: context.text.labelMedium?.copyWith(
                        color: x.onWarning,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(
              title,
              style: context.text.titleMedium?.copyWith(color: x.onAiContainer),
            ),
            if (body != null) ...[
              const SizedBox(height: Space.xs),
              Text(
                body!,
                style: context.text.bodyMedium?.copyWith(
                  color: x.onAiContainer,
                ),
              ),
            ],
            if (child != null) ...[const SizedBox(height: Space.sm), child!],
            if (onWhy != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onWhy,
                  child: const Text('Neden?'),
                ),
              ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final a in actions)
                    a.primary
                        ? FilledButton(
                            onPressed: a.onPressed,
                            style: FilledButton.styleFrom(
                              backgroundColor: x.ai,
                              foregroundColor: x.onAi,
                            ),
                            child: Text(a.label),
                          )
                        : OutlinedButton(
                            onPressed: a.onPressed,
                            child: Text(a.label),
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
