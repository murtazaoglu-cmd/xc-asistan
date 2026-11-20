import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/biometric.dart';
import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';

/// Biyometrik kilit örtüsü. Uygulamanın TÜMÜNÜN üstünü kaplar (içerik gizlenir,
/// gezinme durumu bozulmaz). Açılışta otomatik doğrulama başlatır.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    final ok = await ref.read(appLockProvider.notifier).unlock();
    if (!ok && mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final brand = ref.watch(brandProfileProvider);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandLogo(size: Sizes.logoLarge),
              const SizedBox(height: Space.lg),
              Text('${brand.appName} kilitli', style: context.text.titleLarge),
              const SizedBox(height: Space.sm),
              Text(
                _failed
                    ? 'Kimlik doğrulanamadı.'
                    : 'Devam etmek için kimliğinizi doğrulayın.',
                style: context.text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.xl),
              FilledButton.icon(
                key: const ValueKey('unlock-button'),
                onPressed: _unlock,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Kilidi aç'),
              ),
              const SizedBox(height: Space.md),
              TextButton(
                onPressed: () => ref.read(sessionProvider.notifier).logout(),
                child: const Text('Çıkış yap'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
