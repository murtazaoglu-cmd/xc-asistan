// SAHİBİ: more ajanı. Seyrek ekranların listesi (sol üst menüyle AYNI öğeler ve yetkiler).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/router/nav_items.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider);
    final terms = ref.watch(brandProfileProvider).terms;
    final items = caps == null ? <NavItem>[] : NavCatalog.drawer(caps, terms);
    return AppScaffold(
      title: 'Daha fazla',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        children: [
          for (final i in items)
            ListTile(
              minTileHeight: Sizes.minTouch,
              leading: Icon(i.icon),
              title: Text(i.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(i.path),
            ),
        ],
      ),
    );
  }
}
