// Tokenlardan Material 3 ThemeData üretir. Görünümü değiştirmek için
// tokens.dart düzenlenir; bu dosya yalnızca eşleme mantığıdır.
import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

abstract final class AppTheme {
  /// [primary]: BrandProfile.primaryColor (null ise tokens paleti).
  static ThemeData light({Color? primary}) => _build(
    _withPrimary(AppPalette.lightScheme, primary),
    primary == null
        ? AppPalette.lightExtras
        : AppPalette.lightExtras.copyWith(assistant: primary, info: primary),
  );
  static ThemeData dark({Color? primary}) => _build(
    _withPrimary(AppPalette.darkScheme, primary),
    primary == null
        ? AppPalette.darkExtras
        : AppPalette.darkExtras.copyWith(assistant: primary, info: primary),
  );

  static ColorScheme _withPrimary(ColorScheme s, Color? primary) {
    if (primary == null) return s;
    final onPrimary =
        ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
    return s.copyWith(primary: primary, onPrimary: onPrimary);
  }

  static ThemeData _build(ColorScheme scheme, XcColors extras) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      fontFamily: TypeTokens.fontFamily,
    );

    TextStyle s(double size, FontWeight w, {double? height}) => TextStyle(
      fontSize: size,
      fontWeight: w,
      height: height,
      color: scheme.onSurface,
      fontFamily: TypeTokens.fontFamily,
    );

    final textTheme = base.textTheme.copyWith(
      displayLarge: s(TypeTokens.display, TypeTokens.bold),
      displayMedium: s(TypeTokens.display, TypeTokens.bold),
      headlineLarge: s(TypeTokens.headline, TypeTokens.bold),
      headlineMedium: s(TypeTokens.headline, TypeTokens.bold),
      headlineSmall: s(TypeTokens.title, TypeTokens.bold),
      titleLarge: s(TypeTokens.title, TypeTokens.bold),
      titleMedium: s(TypeTokens.subtitle, TypeTokens.semiBold),
      titleSmall: s(TypeTokens.label, TypeTokens.medium),
      bodyLarge: s(TypeTokens.body, TypeTokens.regular, height: 1.4),
      bodyMedium: s(TypeTokens.bodySmall, TypeTokens.regular, height: 1.4),
      bodySmall: s(
        TypeTokens.caption,
        TypeTokens.regular,
        height: 1.3,
      ).copyWith(color: scheme.onSurfaceVariant),
      labelLarge: s(TypeTokens.label, TypeTokens.medium),
      labelMedium: s(TypeTokens.caption, TypeTokens.medium),
      labelSmall: s(TypeTokens.caption, TypeTokens.medium),
    );

    const minBtn = Size(Sizes.minTouch, Sizes.minTouch);
    final btnShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.md),
    );
    final btnPad = const EdgeInsets.symmetric(horizontal: Space.xl);

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.brightness == Brightness.dark
          ? scheme.surfaceContainerLowest
          : scheme.surfaceContainerLow,
      extensions: <ThemeExtension<dynamic>>[extras],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: minBtn,
          shape: btnShape,
          padding: btnPad,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minBtn,
          shape: btnShape,
          padding: btnPad,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minBtn,
          shape: btnShape,
          padding: btnPad,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: minBtn, shape: btnShape),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: minBtn),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        labelStyle: textTheme.labelMedium,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: Space.sm,
        contentPadding: EdgeInsets.symmetric(horizontal: Space.lg),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      drawerTheme: DrawerThemeData(backgroundColor: scheme.surface),
    );
  }
}
