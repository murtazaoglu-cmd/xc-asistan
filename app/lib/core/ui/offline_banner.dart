import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../api/connectivity.dart';
import '../theme/tokens.dart';

/// İnternet yokken üstte görünen şerit. Kabuk bunu otomatik yerleştirir.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = isOnlineValue(ref.watch(isOnlineProvider));
    final x = context.xc;
    return AnimatedSize(
      duration: Motion.fast,
      child: online
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                color: x.offlineBackground,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.wifi_off,
                      size: Sizes.iconSm,
                      color: x.offlineForeground,
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        'İnternet yok. Son yüklenen veriler gösteriliyor.',
                        style: context.text.bodyMedium?.copyWith(
                          color: x.offlineForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
