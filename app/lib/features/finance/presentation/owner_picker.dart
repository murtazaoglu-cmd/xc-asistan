// Kaydın sahibi (defter) seçici: ödeme/gider kime yazılsın? Varsayılan "Ben" (kendi defterim).
// Aday yoksa (tek kişi) hiç görünmez. Sunucu kuralı (v16): yetkisiz atama sessizce kendi defterine düşer.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../data/finance_models.dart';
import '../data/finance_providers.dart';
import 'form_widgets.dart';

class OwnerPickerBlock extends ConsumerWidget {
  const OwnerPickerBlock({
    super.key,
    required this.projectId,
    required this.selectedId,
    required this.onChanged,
    this.label = 'Kimin defterine yazılsın?',
  });

  /// Projeye bağlı değilse null (yalnız yönetici başkasına atayabilir).
  final String? projectId;

  /// Seçili sahip; null = ben.
  final String? selectedId;

  /// Ben seçilirse null döner.
  final ValueChanged<String?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dir = ref.watch(ownerDirectoryProvider);
    final async = ref.watch(ownerCandidatesProvider(projectId));
    final people = async.value ?? const <OwnerRef>[];
    if (people.length < 2) return const SizedBox.shrink();
    final selfId = dir.selfId;
    final current = selectedId == null || selectedId == selfId
        ? selfId
        : selectedId;
    return FormBlock(
      label: label,
      child: Column(
        key: const Key('owner-picker'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final p in people)
                ChoiceChip(
                  key: Key('owner-${p.id}'),
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text(p.id == selfId ? 'Ben' : p.name),
                  selected: p.id == current,
                  onSelected: (_) => onChanged(p.id == selfId ? null : p.id),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Kayıt seçilen kişinin defterine yazılır; atama yetkiniz yoksa kendi defterinizde kalır.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}
