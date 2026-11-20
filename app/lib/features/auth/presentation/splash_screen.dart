import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';

/// Açılış: jeton doğrulanırken logo + gösterge; sunucuya ulaşılamazsa "Tekrar dene".
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final brand = ref.watch(brandProfileProvider);
    return Scaffold(
      body: Center(
        child: s is SessionBootFailed
            ? ErrorState(
                message: s.message,
                onRetry: () =>
                    ref.read(sessionProvider.notifier).retryBootstrap(),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandLogo(size: Sizes.logoLarge),
                  const SizedBox(height: Space.lg),
                  Text(brand.appName, style: context.text.headlineSmall),
                  const SizedBox(height: Space.xl),
                  const CircularProgressIndicator(),
                ],
              ),
      ),
    );
  }
}
