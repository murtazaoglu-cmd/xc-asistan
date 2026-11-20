// Klavye odağında (Tab) çocuğun çevresine görünür halka çizer; fareyle tıklamada çizmez.
// Satırlar, menü öğeleri ve özel dokunma alanları için (Material düğmelerinin kendi odak vurgusu var).
import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.radius = Radii.sm,
    this.color,
    this.inset = true,
  });
  final Widget child;
  final double radius;
  final Color? color;

  /// Halka çocuğun İÇİNE çizilir (üst Card'ın kırpmasında kesilmesin).
  final bool inset;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ring = widget.color ?? context.colors.primary;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        // Yalnız klavye gezintisinde göster (fare/dokunma odağında gizle).
        final show =
            f &&
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional;
        if (show != _focused) setState(() => _focused = show);
      },
      child: Stack(
        children: [
          widget.child,
          if (_focused)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.radius),
                    border: Border.all(color: ring, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
