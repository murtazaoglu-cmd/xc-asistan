import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../api/api_providers.dart';
import '../theme/tokens.dart';
import 'app_scaffold.dart';
import 'section_card.dart';
import 'states.dart';

/// Henüz geliştirilmemiş feature'ların yer tutucu ekranı. Gerçekten çalışır
/// (menü, rota, geri tuşu). Feature ajanı bu widget'ı kendi ekranıyla DEĞİŞTİRİR.
/// Debug/DEMO derlemede sahip, uçlar ve kullanılacak ortak widget'lar listelenir.
class FeaturePlaceholder extends ConsumerWidget {
  const FeaturePlaceholder({
    super.key,
    required this.title,
    required this.icon,
    this.description,
    this.featureId,
    this.endpoints = const [],
    this.sharedWidgets = const [],
    this.routeInfo,
    this.showMenuButton = true,
  });

  final String title;
  final IconData icon;
  final String? description;
  final String? featureId;
  final List<String> endpoints;
  final List<String> sharedWidgets;

  /// Ör. "id: 42" (detay rotalarında parametre gösterimi).
  final String? routeInfo;
  final bool showMenuButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dev = ref.watch(appConfigProvider).showDevInfo;
    return AppScaffold(
      title: title,
      showMenuButton: showMenuButton,
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          SizedBox(
            height: 320,
            child: EmptyState(
              icon: icon,
              title: '$title yakında',
              message: description ?? 'Bu bölüm hazırlanıyor.',
            ),
          ),
          if (routeInfo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: Center(
                child: Text(routeInfo!, style: context.text.bodySmall),
              ),
            ),
          if (dev)
            SectionCard(
              title: 'Geliştirici bilgisi',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (featureId != null) Text('Feature: features/$featureId/'),
                  if (endpoints.isNotEmpty) ...[
                    const SizedBox(height: Space.sm),
                    Text('Uçlar:', style: context.text.labelLarge),
                    for (final e in endpoints)
                      Text('• $e', style: context.text.bodySmall),
                  ],
                  if (sharedWidgets.isNotEmpty) ...[
                    const SizedBox(height: Space.sm),
                    Text('Ortak widget\'lar:', style: context.text.labelLarge),
                    Text(
                      sharedWidgets.join(', '),
                      style: context.text.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
