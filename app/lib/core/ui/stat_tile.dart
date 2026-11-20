import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// Sayı kutusu (Bugün ekranındaki 4'lü: Randevu / Tahsilat / Teklif / Geciken iş).
/// Renk yalnız vurgudur; etiket ve ikon her zaman vardır.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;

  /// Varsayılan: birincil renk. Geciken iş için `context.colors.error` gibi verilir.
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return Semantics(
      button: onTap != null,
      label: '$label: $value',
      excludeSemantics: true,
      child: Material(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: Sizes.minTouch + 32),
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: context.colors.outlineVariant),
              boxShadow: Shadows.card,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: c, size: Sizes.iconMd),
                const SizedBox(height: Space.xs),
                Text(value, style: context.text.titleLarge?.copyWith(color: c)),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
