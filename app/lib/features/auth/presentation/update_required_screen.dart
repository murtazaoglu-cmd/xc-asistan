import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/api/health_service.dart';
import '../../../core/ui/ui.dart';

/// "Zorunlu güncelleme" ekranı (kanca PASİF: yalnız FORCE_UPDATE_ENABLED=true ve
/// sunucu /health'te minAppVersion bildirirse ve sürüm düşükse açılır).
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final req = ref.watch(updateRequirementProvider).value;
    final store = ref.watch(appConfigProvider).storeUrl;
    return Scaffold(
      body: EmptyState(
        icon: Icons.system_update,
        title: 'Güncelleme gerekli',
        message:
            'Uygulamayı kullanmaya devam etmek için yeni sürüme geçin'
            '${req?.minVersion != null ? ' (en az ${req!.minVersion}).' : '.'}',
        actionLabel: store.isEmpty ? null : 'Güncelle',
        onAction: store.isEmpty
            ? null
            : () => ref.read(linkLauncherProvider).open(Uri.parse(store)),
      ),
    );
  }
}
