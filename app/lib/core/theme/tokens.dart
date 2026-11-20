// TÜM görsel değerlerin (renk, yazı, boşluk, köşe, gölge, boyut) TEK kaynağı.
//
// Kaynak: onaylı görsel tasarım paketi (docs/ARCHITECTURE.md "Tasarım kaynağı").
// Tasarım değişirse YALNIZCA bu dosya değiştirilir; uygulamanın geri kalanı değerleri buradan okur. Başka dosyada renk/ölçü sabiti YAZMAYIN:
//   - Renkler:   Theme.of(context).colorScheme  ya da  context.xc  (anlamsal renkler)
//   - Boşluk:    Space.md, Space.lg ...
//   - Köşe:      Radii.md ...
//   - Yazı:      Theme.of(context).textTheme (boyutlar aşağıda)
import 'package:material_ui/material_ui.dart';

/// Boşluk ölçeği (dp).
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Ekran kenar boşluğu (telefon).
  static const double screenH = 16;
}

/// Köşe yarıçapları.
abstract final class Radii {
  static const double xs = 8;
  static const double sm = 10; // küçük (çip, giriş)
  static const double md = 12; // orta (düğme)
  static const double lg = 16;
  static const double card = 18; // kart
  static const double xl = 22; // büyük (sayfa, alt sayfa)
  static const double xxl = 24;
  static const double pill = 999;
}

/// Sabit ölçüler.
abstract final class Sizes {
  /// Tek el kullanım: en küçük dokunma hedefi (dp).
  static const double minTouch = 48;
  static const double bottomBarHeight = 64;
  static const double assistantButton = 64;
  static const double assistantButtonLift = 18;
  static const double iconSm = 20;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double iconXl = 56;
  static const double chipHeight = 32;
  static const double maxContentWidth = 640;

  /// Geniş ekranda form/ayrıntı gibi tek sütunlu sayfaların en büyük genişliği.
  static const double maxFormWidth = 840;

  /// Geniş ekranda liste/pano sayfalarının en büyük genişliği (web paneli, ortalanır).
  static const double maxWebWidth = 1440;
  static const double logoSmall = 32;
  static const double logoLarge = 88;
}

/// Hareket süreleri.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration skeleton = Duration(milliseconds: 1200);
}

/// Yazı tipi ve ölçekleri. [fontFamily] null ise sistem yazı tipi kullanılır;
/// tasarım özel yazı tipi isterse pubspec'e ekleyip adı buraya yazın.
abstract final class TypeTokens {
  static const String fontFamily =
      'Inter'; // gömülü (assets/fonts), çevrimdışı çalışır

  static const double display = 32;
  static const double headline = 24;
  static const double title = 20;
  static const double subtitle = 16;
  static const double body = 16;
  // İkincil metin: 14, kesin alt sınır 13 (UX raporu H3).
  static const double bodySmall = 14;
  static const double label = 14;
  static const double caption = 13;

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}

/// Gölgeler (açık tema için; koyu temada daha hafif).
abstract final class Shadows {
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x14172033), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6)),
  ];
}

/// Anlamsal renk uzantısı: durum, iskelet, çevrimdışı, asistan düğmesi gibi
/// Material [ColorScheme]'in karşılamadığı renkler. `context.xc` ile okunur.
@immutable
class XcColors extends ThemeExtension<XcColors> {
  const XcColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.neutral,
    required this.neutralContainer,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.offlineBackground,
    required this.offlineForeground,
    required this.assistant,
    required this.onAssistant,
    required this.ai,
    required this.onAi,
    required this.aiContainer,
    required this.onAiContainer,
    required this.navy,
    required this.navySecondary,
    required this.onNavy,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color neutral;
  final Color neutralContainer;
  final Color skeletonBase;
  final Color skeletonHighlight;
  final Color offlineBackground;
  final Color offlineForeground;

  /// Alt çubuktaki büyük orta "Asistan" düğmesi.
  final Color assistant;
  final Color onAssistant;

  /// Yapay zekâ vurgusu (Asistan Özeti, öneri kartları) ve açık zemini.
  final Color ai;
  final Color onAi;
  final Color aiContainer;
  final Color onAiContainer;

  /// Lacivert yüzeyler (saha ekranı zemini, koyu şeritler).
  final Color navy;
  final Color navySecondary;
  final Color onNavy;

  @override
  XcColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? neutral,
    Color? neutralContainer,
    Color? skeletonBase,
    Color? skeletonHighlight,
    Color? offlineBackground,
    Color? offlineForeground,
    Color? assistant,
    Color? onAssistant,
    Color? ai,
    Color? onAi,
    Color? aiContainer,
    Color? onAiContainer,
    Color? navy,
    Color? navySecondary,
    Color? onNavy,
  }) {
    return XcColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      neutral: neutral ?? this.neutral,
      neutralContainer: neutralContainer ?? this.neutralContainer,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
      offlineBackground: offlineBackground ?? this.offlineBackground,
      offlineForeground: offlineForeground ?? this.offlineForeground,
      assistant: assistant ?? this.assistant,
      onAssistant: onAssistant ?? this.onAssistant,
      ai: ai ?? this.ai,
      onAi: onAi ?? this.onAi,
      aiContainer: aiContainer ?? this.aiContainer,
      onAiContainer: onAiContainer ?? this.onAiContainer,
      navy: navy ?? this.navy,
      navySecondary: navySecondary ?? this.navySecondary,
      onNavy: onNavy ?? this.onNavy,
    );
  }

  @override
  XcColors lerp(ThemeExtension<XcColors>? other, double t) {
    if (other is! XcColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return XcColors(
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      successContainer: l(successContainer, other.successContainer),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      warningContainer: l(warningContainer, other.warningContainer),
      info: l(info, other.info),
      onInfo: l(onInfo, other.onInfo),
      infoContainer: l(infoContainer, other.infoContainer),
      neutral: l(neutral, other.neutral),
      neutralContainer: l(neutralContainer, other.neutralContainer),
      skeletonBase: l(skeletonBase, other.skeletonBase),
      skeletonHighlight: l(skeletonHighlight, other.skeletonHighlight),
      offlineBackground: l(offlineBackground, other.offlineBackground),
      offlineForeground: l(offlineForeground, other.offlineForeground),
      assistant: l(assistant, other.assistant),
      onAssistant: l(onAssistant, other.onAssistant),
      ai: l(ai, other.ai),
      onAi: l(onAi, other.onAi),
      aiContainer: l(aiContainer, other.aiContainer),
      onAiContainer: l(onAiContainer, other.onAiContainer),
      navy: l(navy, other.navy),
      navySecondary: l(navySecondary, other.navySecondary),
      onNavy: l(onNavy, other.onNavy),
    );
  }
}

/// Renk paletleri (onaylı tasarım: design-tokens.json + design-board.png).
/// Not: beyaz üzerindeki #3B82F6 büyük/kalın metinde AA geçer; küçük metin için
/// ikincil metin rengi (onSurface/onSurfaceVariant) kullanılır.
abstract final class AppPalette {
  // ---- Açık tema ----
  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF3B82F6),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEAF1FF),
    onPrimaryContainer: Color(0xFF172033),
    secondary: Color(0xFF24324A),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE4E9F1),
    onSecondaryContainer: Color(0xFF172033),
    tertiary: Color(0xFF8B5CF6),
    onTertiary: Color(0xFFFFFFFF),
    error: Color(0xFFEF4444),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFDE8E8),
    onErrorContainer: Color(0xFF7F1D1D),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF172033),
    onSurfaceVariant: Color(0xFF718096),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF5F7FB), // sayfa arka planı
    surfaceContainer: Color(0xFFF0F3F9),
    surfaceContainerHigh: Color(0xFFE9EEF6),
    surfaceContainerHighest: Color(0xFFE4E9F1),
    outline: Color(0xFF718096),
    outlineVariant: Color(0xFFE4E9F1), // çizgi
    shadow: Color(0xFF172033),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF172033),
    onInverseSurface: Color(0xFFF5F7FB),
    inversePrimary: Color(0xFF60A5FA),
  );

  static const XcColors lightExtras = XcColors(
    success: Color(0xFF16A34A),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDCFCE7),
    warning: Color(0xFFF59E0B),
    onWarning: Color(0xFF172033),
    warningContainer: Color(0xFFFEF3C7),
    info: Color(0xFF3B82F6),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFEAF1FF),
    neutral: Color(0xFF718096),
    neutralContainer: Color(0xFFE9EEF6),
    skeletonBase: Color(0xFFE4E9F1),
    skeletonHighlight: Color(0xFFF5F7FB),
    offlineBackground: Color(0xFF172033),
    offlineForeground: Color(0xFFFFFFFF),
    assistant: Color(0xFF3B82F6),
    onAssistant: Color(0xFFFFFFFF),
    ai: Color(0xFF8B5CF6),
    onAi: Color(0xFFFFFFFF),
    aiContainer: Color(0xFFF1EBFF),
    onAiContainer: Color(0xFF4C2A9A),
    navy: Color(0xFF172033),
    navySecondary: Color(0xFF24324A),
    onNavy: Color(0xFFFFFFFF),
  );

  // ---- Koyu tema ----
  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF60A5FA),
    onPrimary: Color(0xFF0B1324),
    primaryContainer: Color(0xFF1E3A66),
    onPrimaryContainer: Color(0xFFDCE9FF),
    secondary: Color(0xFF94A3B8),
    onSecondary: Color(0xFF0B1324),
    secondaryContainer: Color(0xFF334155),
    onSecondaryContainer: Color(0xFFE2E8F0),
    tertiary: Color(0xFFA78BFA),
    onTertiary: Color(0xFF1E1147),
    error: Color(0xFFF87171),
    onError: Color(0xFF3B0A0A),
    errorContainer: Color(0xFF5B1A1A),
    onErrorContainer: Color(0xFFFDE8E8),
    surface: Color(0xFF1E2938),
    onSurface: Color(0xFFF1F5F9),
    onSurfaceVariant: Color(0xFFA3B1C6),
    surfaceContainerLowest: Color(0xFF0B1324), // sayfa arka planı
    surfaceContainerLow: Color(0xFF0B1324),
    surfaceContainer: Color(0xFF1E2938),
    surfaceContainerHigh: Color(0xFF334155), // kart
    surfaceContainerHighest: Color(0xFF3F4F66),
    outline: Color(0xFF94A3B8),
    outlineVariant: Color(0xFF334155),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFF1F5F9),
    onInverseSurface: Color(0xFF172033),
    inversePrimary: Color(0xFF3B82F6),
  );

  static const XcColors darkExtras = XcColors(
    success: Color(0xFF22C55E),
    onSuccess: Color(0xFF052E16),
    successContainer: Color(0xFF14532D),
    warning: Color(0xFFFBBF24),
    onWarning: Color(0xFF3A2800),
    warningContainer: Color(0xFF5C4100),
    info: Color(0xFF60A5FA),
    onInfo: Color(0xFF0B1324),
    infoContainer: Color(0xFF1E3A66),
    neutral: Color(0xFFA3B1C6),
    neutralContainer: Color(0xFF334155),
    skeletonBase: Color(0xFF334155),
    skeletonHighlight: Color(0xFF3F4F66),
    offlineBackground: Color(0xFFF1F5F9),
    offlineForeground: Color(0xFF0B1324),
    assistant: Color(0xFF60A5FA),
    onAssistant: Color(0xFF0B1324),
    ai: Color(0xFFA78BFA),
    onAi: Color(0xFF1E1147),
    aiContainer: Color(0xFF2E2358),
    onAiContainer: Color(0xFFE4DBFF),
    navy: Color(0xFF0B1324),
    navySecondary: Color(0xFF1E2938),
    onNavy: Color(0xFFF1F5F9),
  );
}

/// Kolay erişim: `context.xc.success`, `context.colors.primary`, `context.text.bodyLarge`.
extension XcThemeX on BuildContext {
  XcColors get xc => Theme.of(this).extension<XcColors>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}
