import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// Başlıklı kart bölümü. [onTap] verilirse kartın tamamı dokunulabilir (≥48 dp).
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.onTap,
    this.margin,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final header = (title == null && trailing == null)
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Row(
              children: [
                if (title != null)
                  Expanded(child: Text(title!, style: context.text.titleMedium))
                else
                  const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
          );
    final inner = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [if (header != null) header, child],
      ),
    );
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? inner
          : InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Sizes.minTouch),
                child: inner,
              ),
            ),
    );
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}
