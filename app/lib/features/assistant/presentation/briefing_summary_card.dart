// DIŞA AÇIK widget: Bugün ekranına takılan "Asistan Özeti" kartı (bkz. docs/ARCHITECTURE.md §13).
//   BriefingSummaryCard()                       // dokununca /assistant/briefing
//   BriefingSummaryCard(onOpen: () => ...)      // özel yönlendirme
// Kendi verisini GET /assistant/briefing/today ile çeker; iskelet / hata (Tekrar dene) / boş gün
// durumlarını kendisi yönetir. Rol süzgeci: saha yalnız randevu ve geciken iş sayısını, para ve
// müdür içeriği olmadan görür.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../application/access.dart';
import '../application/assistant_providers.dart';
import '../application/assistant_routes_paths.dart';
import 'widgets/assistant_ui.dart';
import 'widgets/briefing_views.dart';

class BriefingSummaryCard extends ConsumerWidget {
  const BriefingSummaryCard({super.key, this.onOpen, this.showStats = true});

  /// false: 4 sayı karosu çizilmez (Bugün ekranı kendi karolarını gösterir).
  final bool showStats;

  /// Verilmezse Brifing ekranı açılır.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(briefingTodayProvider);
    final access = ref.watch(assistantAccessProvider);
    void open() =>
        onOpen != null ? onOpen!() : context.push(AssistantPaths.briefing);

    return async.when(
      loading: () => const SkeletonBox(height: 168, radius: Radii.card),
      error: (e, _) => AiCard(
        kind: AiCardKind.summary,
        title: 'Brifing yüklenemedi',
        body: errorText(e),
        actions: [
          AiCardAction(
            'Tekrar dene',
            () => ref.invalidate(briefingTodayProvider),
          ),
        ],
      ),
      data: (b) {
        final bullets = briefingBullets(b, access, context.terms);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AiCard(
              kind: AiCardKind.summary,
              title: b.title.isEmpty ? 'Günaydın' : b.title,
              body: bullets.isEmpty
                  ? null
                  : bullets.map((e) => '• $e').join('\n'),
              actions: [AiCardAction('Brifingi aç', open, primary: true)],
            ),
            if (showStats) ...[
              const SizedBox(height: Space.md),
              BriefingStatRow(briefing: b, access: access),
            ],
          ],
        );
      },
    );
  }
}
