import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import 'phone_actions.dart';

/// Adres: dokununca haritada yol tarifi açar. Koordinat varsa onu kullanır.
/// Adres de koordinat da yoksa hiçbir şey çizmez.
class AddressActions extends ConsumerWidget {
  const AddressActions({
    super.key,
    this.address,
    this.lat,
    this.lng,
    this.showButton = false,
  });

  final String? address;
  final double? lat;
  final double? lng;

  /// Adresin yanında ayrı "Yol tarifi" düğmesi göster.
  final bool showButton;

  bool get _hasTarget =>
      (lat != null && lng != null) ||
      (address != null && address!.trim().isNotEmpty);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_hasTarget) return const SizedBox.shrink();
    final launcher = ref.read(contactLauncherProvider);
    Future<void> open() async {
      final ok = await launcher.directions(
        address: address,
        lat: lat,
        lng: lng,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Harita uygulaması açılamadı.')),
        );
      }
    }

    final label = (address != null && address!.trim().isNotEmpty)
        ? address!.trim()
        : 'Konumu haritada aç';
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: open,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Sizes.minTouch),
              child: Row(
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: Sizes.iconSm,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: context.text.bodyLarge?.copyWith(
                        color: context.colors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showButton)
          OutlinedButton.icon(
            onPressed: open,
            icon: const Icon(Icons.directions, size: Sizes.iconSm),
            label: const Text('Yol tarifi'),
          ),
      ],
    );
  }
}
