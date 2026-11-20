// Ana-ayrıntı (master-detail) düzeni, YÖNLENDİRME katmanından: geniş pencerede (>= 1200 dp) liste
// sekmesinin ana ekranı solda KALICI bölme olarak gösterilir; ayrıntı rotaları (/customers/123,
// /jobs/offers/9 ...) sağ bölmedeki dal gezgininde açılır. Özellik ekranları değişmez: liste ekranı
// aynı widget'tır, satıra dokunma yine `context.push(rota)` yapar, URL ve geri/ileri düğmeleri aynıdır.
//
// Hangi liste hangi yol önekiyle eşleşir: `masterPanesProvider` (kompozisyon kökü `app_wiring.dart`
// doldurur; core hiçbir özelliği içe aktarmaz).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

class MasterPane {
  const MasterPane({
    required this.prefix,
    required this.builder,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptyMessage = 'Soldaki listeden bir kayıt seçin.',
  });

  /// Liste kök yolu (`/customers`). Ayrıntı yolları bunun altındadır.
  final String prefix;
  final WidgetBuilder builder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  bool matches(String location) =>
      location == prefix || location.startsWith('$prefix/');
  bool isRoot(String location) => location == prefix;
}

final masterPanesProvider = Provider<List<MasterPane>>((ref) => const []);

MasterPane? matchMasterPane(List<MasterPane> panes, String location) {
  for (final p in panes) {
    if (p.matches(location)) return p;
  }
  return null;
}

/// Sağ bölmede kayıt seçilmemişken gösterilen boş durum.
class MasterDetailPlaceholder extends StatelessWidget {
  const MasterDetailPlaceholder({super.key, required this.pane});
  final MasterPane pane;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('master-detail-placeholder'),
      color: c.surfaceContainerLow,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(pane.emptyIcon, size: Sizes.iconXl, color: c.outline),
          const SizedBox(height: Space.md),
          Text(
            pane.emptyTitle,
            style: context.text.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.xs),
          Text(
            pane.emptyMessage,
            style: context.text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Liste sütunu genişliği (pencereye göre 360–460 dp).
double masterPaneWidth(double windowWidth) =>
    (windowWidth * 0.3).clamp(360.0, 460.0);
