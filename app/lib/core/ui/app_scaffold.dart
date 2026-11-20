import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import 'shell_controller.dart';

/// Tüm ekranların iskeleti: başlık çubuğu + gövde + (isteğe bağlı) alt eylem çubuğu.
///
/// - Kabuk içindeki kök ekranlarda sol üstte menü (çekmece) düğmesi, iç sayfalarda geri oku.
/// - [bottomBar] gövdenin ALTINDA, klavye açılınca da görünür kalır (gövde klavyenin üstüne
///   sıkışır): form ekranlarında [BottomSaveBar] buraya konur.
/// - İçerik telefonda/tablette [Sizes.maxContentWidth] ile sınırlanır; geniş ekranda (web paneli)
///   form/ayrıntı sayfaları [Sizes.maxFormWidth], [wideLayout] isteyen liste/pano sayfaları
///   [Sizes.maxWebWidth] ile sınırlanıp ortalanır. Sütunlara bölme sayfanın işidir
///   (`ResponsiveColumns`, `DataTableView`).
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.title,
    this.titleWidget,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomBar,
    this.bottom,
    this.leading,
    this.showMenuButton = true,
    this.constrainWidth = true,
    this.wideLayout = false,
  });

  final String? title;
  final Widget? titleWidget;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomBar;
  final PreferredSizeWidget? bottom;
  final Widget? leading;

  /// Kök ekranda menü düğmesi göster (kabuk yoksa görünmez).
  final bool showMenuButton;
  final bool constrainWidth;

  /// Geniş ekranda tüm içerik alanını (en çok [Sizes.maxWebWidth]) kullan: liste/pano/tablo sayfaları.
  final bool wideLayout;

  @override
  Widget build(BuildContext context) {
    final shell = ShellController.maybeOf(context);
    final canPop = Navigator.of(context).canPop();
    Widget? lead = leading;
    if (lead == null) {
      if (canPop) {
        lead = const BackButton();
      } else if (showMenuButton && shell != null && !shell.wide) {
        lead = IconButton(
          tooltip: 'Menü',
          icon: const Icon(Icons.menu),
          onPressed: shell.openDrawer,
        );
      }
    }

    Widget content = body;
    if (constrainWidth) {
      final isWide = shell?.wide ?? false;
      final maxW = !isWide
          ? Sizes.maxContentWidth
          : (wideLayout ? Sizes.maxWebWidth : Sizes.maxFormWidth);
      content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: body,
        ),
      );
    }

    return Scaffold(
      appBar:
          (title == null &&
              titleWidget == null &&
              actions == null &&
              lead == null)
          ? null
          : AppBar(
              leading: lead,
              automaticallyImplyLeading: false,
              title: titleWidget ?? (title == null ? null : Text(title!)),
              actions: actions,
              bottom: bottom,
            ),
      // Birden çok ekran FAB taşır; sayfa geçişinde aynı Hero etiketi çakışmasın.
      floatingActionButton: floatingActionButton == null
          ? null
          : HeroMode(enabled: false, child: floatingActionButton!),
      body: SafeArea(
        top: false,
        bottom: bottomBar == null,
        child: Column(
          children: [
            Expanded(child: content),
            if (bottomBar != null) bottomBar!,
          ],
        ),
      ),
    );
  }
}
