import 'package:material_ui/material_ui.dart';

/// Uyarlanabilir yerleşim eşikleri (mantıksal piksel, GENİŞLİĞE göre).
/// Kabuk: dar = alt çubuk + çekmece; geniş = sol kenar menüsü + içerik alanı.
abstract final class Breakpoints {
  /// Bu genişlikten itibaren "geniş ekran" (masaüstü / web / yatay tablet).
  static const double wide = 900;

  /// Bu genişlikten itibaren "çok geniş": web ajanı iki sütunlu ana-ayrıntı düzeni için kullanabilir.
  static const double extraWide = 1280;

  /// Ana-ayrıntı (liste solda, ayrıntı sağda) için PENCERE genişliği (>= 1200 dp).
  static const double split = 1200;

  /// Üç sütunlu panolar (Bugün, Raporlar) için İÇERİK alanı genişliği.
  static const double threeColumn = 1100;

  /// İki sütunlu panolar için içerik alanı genişliği.
  static const double twoColumn = 720;

  /// Web yönetim panelinde içeriğin en büyük genişliği (ortalanır).
  static const double maxWebContent = 1440;

  static bool isWideWidth(double width) => width >= wide;

  /// Ekran genişliğine göre geniş mi (kabuğun ölçüsünden değil, pencereden).
  static bool isWide(BuildContext context) =>
      isWideWidth(MediaQuery.sizeOf(context).width);

  static bool isSplit(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= split;

  static bool isExtraWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= extraWide;
}
