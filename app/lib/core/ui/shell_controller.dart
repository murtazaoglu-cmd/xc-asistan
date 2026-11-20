import 'package:flutter/widgets.dart';

/// Kabuk (alt çubuk + çekmece) ekranların sol üst menü düğmesinin çekmeceyi
/// açabilmesi için sağlar. Kabuğun dışındaki ekranlarda (giriş vb.) yoktur.
class ShellController extends InheritedWidget {
  const ShellController({
    super.key,
    required this.openDrawer,
    this.wide = false,
    this.split = false,
    required super.child,
  });

  final VoidCallback openDrawer;

  /// Geniş ekran düzeni (sol kenar menüsü): çekmece düğmesi gösterilmez.
  final bool wide;

  /// Ana-ayrıntı düzeni açık (içerik alanı >= [Breakpoints.split] ve listeli bir sekme):
  /// ayrıntı sayfaları sağ bölmede açılır.
  final bool split;

  static ShellController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellController>();

  @override
  bool updateShouldNotify(ShellController oldWidget) =>
      wide != oldWidget.wide || split != oldWidget.split;
}
