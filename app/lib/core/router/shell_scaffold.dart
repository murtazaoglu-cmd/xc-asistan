// Kabuk: alt çubuk (5 sekme, ortada büyük Asistan) + sol üst çekmece + çevrimdışı şeridi.
// Sekme durumu StatefulShellRoute ile korunur. Android geri tuşu: iç sayfadan bir üst
// sayfaya; sekme köküyse "Bugün"e; "Bugün"deyse uygulamadan çık.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/session.dart';
import '../config/brand_profile.dart';
import '../theme/theme_mode_provider.dart';
import '../theme/tokens.dart';
import '../ui/breakpoints.dart';
import '../ui/confirm_dialog.dart';
import '../ui/focus_ring.dart';
import '../ui/offline_banner.dart';
import '../ui/shell_controller.dart';
import 'command_palette.dart';
import 'master_detail.dart';
import 'app_router.dart' show rootNavigatorKey;
import 'nav_items.dart';
import 'routes.dart';

class ShellScaffold extends ConsumerStatefulWidget {
  const ShellScaffold({
    super.key,
    required this.location,
    required this.navigationShell,
  });

  final String location;
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends ConsumerState<ShellScaffold> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Kabuğun içeriği (dal gezginleri). Düzen (tek bölme / ana-ayrıntı) değişince yeniden
  /// kurulmasın, sekme durumları korunsun diye GlobalKey ile taşınır.
  final GlobalKey _contentKey = GlobalKey(debugLabel: 'shell-content');

  bool _paletteOpen = false;
  List<PaletteEntry> _paletteEntries = const [];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool get _editingText {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Klavye kısayolları (yalnız geniş ekranda anlamlı; donanım klavyesi olan her yerde çalışır):
  ///   Ctrl/Cmd+K veya `/` (metin girişinde değilken): hızlı git paleti
  ///   Esc (açık pencere yokken, ana-ayrıntıda): ayrıntı bölmesini kapat (liste köküne dön)
  bool _onKey(KeyEvent e) {
    if (!mounted || e is! KeyDownEvent) return false;
    final kb = HardwareKeyboard.instance;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.keyK &&
        (kb.isControlPressed || kb.isMetaPressed)) {
      _openPalette();
      return true;
    }
    if (k == LogicalKeyboardKey.slash &&
        !kb.isControlPressed &&
        !kb.isMetaPressed &&
        !kb.isAltPressed &&
        !_editingText) {
      _openPalette();
      return true;
    }
    if (k == LogicalKeyboardKey.escape && !_editingText) {
      final panes = ref.read(masterPanesProvider);
      final pane = matchMasterPane(panes, widget.location);
      final root = rootNavigatorKey.currentState;
      if (pane != null &&
          !pane.isRoot(widget.location) &&
          Breakpoints.isSplit(context) &&
          !(root?.canPop() ?? false)) {
        context.go(pane.prefix);
        return true;
      }
    }
    return false;
  }

  void _openPalette() {
    if (_paletteOpen || !mounted) return;
    final root = rootNavigatorKey.currentState;
    if (root?.canPop() ?? false) return; // başka bir pencere/form açık
    _paletteOpen = true;
    showCommandPalette(context, _paletteEntries).whenComplete(() {
      _paletteOpen = false;
    });
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _onBack(bool didPop) {
    if (didPop) return;
    context.go(Routes.today);
  }

  void _onTabTap(NavItem item) {
    final shell = widget.navigationShell;
    if (item.branchIndex < Branches.tabCount) {
      // Sekme: son konumu geri yükle; aktif sekmeye tekrar dokunma → köke dön.
      shell.goBranch(
        item.branchIndex,
        initialLocation: item.matches(widget.location),
      );
    } else {
      context.go(item.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capabilitiesProvider);
    final terms = ref.watch(brandProfileProvider).terms;
    if (caps == null) return const SizedBox.shrink();
    final bottomItems = NavCatalog.bottom(caps, terms);
    final drawerItems = NavCatalog.drawer(caps, terms);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // Geniş ekran (>= 900): alt çubuk + çekmece yerine sol kenar menüsü.
    final wide = Breakpoints.isWide(context);

    Future<void> logout() async {
      final ok = await ConfirmDialog.show(
        context,
        title: 'Çıkış yapılsın mı?',
        message: 'Bu cihazdaki oturum kapatılır.',
        confirmLabel: 'Çıkış yap',
        destructive: true,
      );
      if (ok) await ref.read(sessionProvider.notifier).logout();
    }

    final navItems = [
      ...bottomItems,
      ...drawerItems.where((d) => !bottomItems.any((b) => b.id == d.id)),
    ];
    final themeMode = ref.watch(themeModeProvider);
    _paletteEntries = [
      for (final item in navItems)
        PaletteEntry(
          id: item.id,
          label: item.label,
          hint: item.path,
          icon: item.icon,
          onSelect: () => _onTabTap(item),
        ),
      // Web'de yerel bildirim yok: uygulama içi gelen kutusu ve brifing buradan da açılır.
      if (RouteGuard.isAllowed('/assistant/inbox', caps))
        PaletteEntry(
          id: 'inbox',
          label: 'Gelen kutusu',
          hint: 'Bildirimler ve hatırlatmalar',
          keywords: 'bildirim zil hatırlatma',
          icon: Icons.notifications_none,
          onSelect: () => context.go('/assistant/inbox'),
        ),
      if (RouteGuard.isAllowed('/assistant/briefing', caps))
        PaletteEntry(
          id: 'briefing',
          label: 'Günün brifingi',
          keywords: 'özet sabah',
          icon: Icons.wb_sunny_outlined,
          onSelect: () => context.go('/assistant/briefing'),
        ),
      PaletteEntry(
        id: 'theme',
        label: themeMode == ThemeMode.dark
            ? 'Açık temaya geç'
            : 'Koyu temaya geç',
        keywords: 'tema görünüm karanlık aydınlık',
        icon: themeMode == ThemeMode.dark
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined,
        onSelect: () => ref
            .read(themeModeProvider.notifier)
            .set(
              themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
            ),
      ),
      PaletteEntry(
        id: 'logout',
        label: 'Çıkış yap',
        icon: Icons.logout,
        onSelect: logout,
      ),
    ];

    // Ana-ayrıntı: pencere >= 1200 dp ve liste sekmelerinden biri.
    final panes = ref.watch(masterPanesProvider);
    final pane = wide && Breakpoints.isSplit(context)
        ? matchMasterPane(panes, widget.location)
        : null;
    final atMasterRoot = pane != null && pane.isRoot(widget.location);

    final content = KeyedSubtree(
      key: _contentKey,
      child: Column(
        children: [
          SafeArea(bottom: false, child: const OfflineBanner()),
          Expanded(child: widget.navigationShell),
        ],
      ),
    );

    Widget wideBody;
    if (pane == null) {
      wideBody = content;
    } else {
      final windowW = MediaQuery.sizeOf(context).width;
      wideBody = Row(
        children: [
          SizedBox(
            width: masterPaneWidth(windowW),
            child: KeyedSubtree(
              key: ValueKey('master-${pane.prefix}'),
              child: pane.builder(context),
            ),
          ),
          VerticalDivider(width: 1, color: context.colors.outlineVariant),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Kök konumda dal gezgini gizli tutulur (durumu korunur), yerine boş durum çizilir.
                Offstage(offstage: atMasterRoot, child: content),
                if (atMasterRoot)
                  Positioned.fill(child: MasterDetailPlaceholder(pane: pane)),
              ],
            ),
          ),
        ],
      );
    }

    return ShellController(
      openDrawer: _openDrawer,
      wide: wide,
      split: pane != null,
      child: PopScope(
        canPop: widget.location == Routes.today,
        onPopInvokedWithResult: (didPop, _) => _onBack(didPop),
        child: Scaffold(
          key: _scaffoldKey,
          // İç ekranların kendi Scaffold'u klavyeyi yönetir.
          resizeToAvoidBottomInset: false,
          drawer: wide
              ? null
              : AppDrawer(
                  items: drawerItems,
                  location: widget.location,
                  onSelect: (item) {
                    Navigator.of(context).pop();
                    context.go(item.path);
                  },
                ),
          body: wide
              ? Row(
                  children: [
                    SideNav(
                      items: navItems,
                      location: widget.location,
                      onTap: _onTabTap,
                      onLogout: logout,
                      onSearch: _openPalette,
                    ),
                    Expanded(child: wideBody),
                  ],
                )
              : content,
          bottomNavigationBar: wide || keyboardOpen
              ? null
              : AppBottomBar(
                  items: bottomItems,
                  location: widget.location,
                  onTap: _onTabTap,
                ),
        ),
      ),
    );
  }
}

/// Geniş ekran sol kenar menüsü (lacivert). Tüm öğeler tek listede; Asistan vurgulu.
/// İSKELET: web ajanı daraltılabilir menü, arama/komut çubuğu vb. ekler.
class SideNav extends ConsumerWidget {
  const SideNav({
    super.key,
    required this.items,
    required this.location,
    required this.onTap,
    required this.onLogout,
    this.onSearch,
  });

  static const double width = 248;

  final List<NavItem> items;
  final String location;
  final void Function(NavItem) onTap;
  final VoidCallback onLogout;

  /// Hızlı git paletini açar (Ctrl+K).
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final x = context.xc;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final brand = ref.watch(brandProfileProvider);
    final user = ref.watch(currentUserProvider);
    const fg = Color(0xFFE4E9F1);
    return SizedBox(
      width: width,
      child: Material(
        color: x.navy,
        child: SafeArea(
          right: false,
          child: Semantics(
            container: true,
            label: 'Ana menü',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Row(
                    children: [
                      const BrandLogo(size: 36),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text(
                          brand.appName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleMedium?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onSearch != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.sm,
                      0,
                      Space.sm,
                      Space.sm,
                    ),
                    child: _SearchHint(onTap: onSearch!),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                    children: [
                      for (final item in items)
                        _SideNavTile(
                          item: item,
                          selected: item.matches(location),
                          onTap: () => onTap(item),
                        ),
                    ],
                  ),
                ),
                if (user != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: Space.lg,
                      right: Space.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: '${user.name} · ${user.role.label}',
                            child: Text(
                              '${user.name} · ${user.role.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(
                                color: fg,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('side-theme'),
                          tooltip: isDark ? 'Açık tema' : 'Koyu tema',
                          color: fg,
                          icon: Icon(
                            isDark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                            size: Sizes.iconSm,
                          ),
                          onPressed: () => ref
                              .read(themeModeProvider.notifier)
                              .set(isDark ? ThemeMode.light : ThemeMode.dark),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  key: const ValueKey('side-logout'),
                  minTileHeight: Sizes.minTouch,
                  iconColor: fg,
                  textColor: fg,
                  leading: const Icon(Icons.logout),
                  title: const Text('Çıkış yap'),
                  onTap: onLogout,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kenar menüsünün üstündeki "Ara / hızlı git" kutusu (tıklayınca palet açılır; Ctrl+K, `/`).
class _SearchHint extends StatelessWidget {
  const _SearchHint({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    return Tooltip(
      message: 'Hızlı git (Ctrl+K veya /)',
      child: FocusRing(
        radius: Radii.md,
        color: Colors.white,
        child: Material(
          color: x.navySecondary.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(Radii.md),
          child: InkWell(
            key: const ValueKey('side-search'),
            borderRadius: BorderRadius.circular(Radii.md),
            hoverColor: Colors.white.withValues(alpha: 0.08),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm + 2,
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Color(0xFFB7C3D5), size: 20),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      'Hızlı git',
                      style: context.text.bodyMedium?.copyWith(
                        color: const Color(0xFFB7C3D5),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF52627D)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Ctrl K',
                      style: context.text.labelSmall?.copyWith(
                        color: const Color(0xFFB7C3D5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideNavTile extends StatelessWidget {
  const _SideNavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    final bg = selected
        ? (item.isCenter ? x.assistant : x.navySecondary)
        : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        excludeSemantics: true,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.md),
          child: FocusRing(
            radius: Radii.md,
            color: Colors.white,
            child: InkWell(
              key: ValueKey('nav-${item.id}'),
              borderRadius: BorderRadius.circular(Radii.md),
              hoverColor: Colors.white.withValues(alpha: 0.08),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Sizes.minTouch),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  child: Row(
                    children: [
                      Icon(
                        selected ? item.selectedIcon : item.icon,
                        color: Colors.white,
                        size: Sizes.iconMd,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: selected
                                ? TypeTokens.bold
                                : TypeTokens.medium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Alt çubuk. Ortadaki (isCenter) öğe büyük, yukarı taşan yuvarlak düğmedir.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.items,
    required this.location,
    required this.onTap,
  });

  final List<NavItem> items;
  final String location;
  final void Function(NavItem) onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Semantics(
          container: true,
          label: 'Ana menü',
          child: SizedBox(
            height: Sizes.bottomBarHeight,
            child: Row(
              children: [
                for (final item in items)
                  Expanded(
                    child: item.isCenter
                        ? _CenterButton(
                            item: item,
                            selected: item.matches(location),
                            onTap: () => onTap(item),
                          )
                        : _BarItem(
                            item: item,
                            selected: item.matches(location),
                            onTap: () => onTap(item),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = selected ? c.primary : c.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('nav-${item.id}'),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.selectedIcon : item.icon,
              color: color,
              size: Sizes.iconMd,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(
                color: color,
                fontWeight: selected ? TypeTokens.bold : TypeTokens.medium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            top: -Sizes.assistantButtonLift,
            child: GestureDetector(
              key: ValueKey('nav-${item.id}'),
              onTap: onTap,
              child: Container(
                width: Sizes.assistantButton,
                height: Sizes.assistantButton,
                decoration: BoxDecoration(
                  color: x.assistant,
                  shape: BoxShape.circle,
                  boxShadow: Shadows.raised,
                  border: selected
                      ? Border.all(color: context.colors.surface, width: 3)
                      : null,
                ),
                child: Icon(
                  item.selectedIcon,
                  color: x.onAssistant,
                  size: Sizes.iconLg,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            child: Text(
              item.label,
              style: context.text.labelMedium?.copyWith(
                color: selected
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
                fontWeight: TypeTokens.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sol üst çekmece: kullanıcı başlığı, seyrek ekranlar, çıkış.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({
    super.key,
    required this.items,
    required this.location,
    required this.onSelect,
  });

  final List<NavItem> items;
  final String location;
  final void Function(NavItem) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final brand = ref.watch(brandProfileProvider);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Row(
                children: [
                  const BrandLogo(size: 48),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(brand.appName, style: context.text.titleMedium),
                        if (user != null) ...[
                          Text(
                            user.name,
                            style: context.text.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(user.role.label, style: context.text.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            for (final item in items)
              ListTile(
                key: ValueKey('drawer-${item.id}'),
                minTileHeight: Sizes.minTouch,
                leading: Icon(
                  item.matches(location) ? item.selectedIcon : item.icon,
                ),
                title: Text(item.label),
                selected: item.matches(location),
                onTap: () => onSelect(item),
              ),
            const Spacer(),
            const Divider(),
            ListTile(
              key: const ValueKey('drawer-logout'),
              minTileHeight: Sizes.minTouch,
              leading: const Icon(Icons.logout),
              title: const Text('Çıkış yap'),
              onTap: () async {
                final nav = Navigator.of(context);
                final ok = await ConfirmDialog.show(
                  context,
                  title: 'Çıkış yapılsın mı?',
                  message: 'Bu cihazdaki oturum kapatılır.',
                  confirmLabel: 'Çıkış yap',
                  destructive: true,
                );
                if (ok) {
                  nav.pop();
                  await ref.read(sessionProvider.notifier).logout();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
