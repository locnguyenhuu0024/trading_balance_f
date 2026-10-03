import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Shared grayscale roles for screen-level presentation.
class AppPalette {
  const AppPalette._({
    required this.background,
    required this.surface,
    required this.raised,
    required this.ink,
    required this.muted,
    required this.border,
    required this.positive,
    required this.negative,
    required this.warning,
    required this.onStrong,
  });

  factory AppPalette.of(BuildContext context) =>
      AppPalette.forBrightness(Theme.of(context).brightness == Brightness.dark);

  factory AppPalette.forBrightness(bool isDark) => isDark ? dark : light;

  static const light = AppPalette._(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF7F7F7),
    raised: Color(0xFFFFFFFF),
    ink: Color(0xFF151515),
    muted: Color(0xFF595959),
    border: Color(0xFFD6D6D6),
    positive: Color(0xFF303030),
    negative: Color(0xFF646464),
    warning: Color(0xFF595959),
    onStrong: Color(0xFFFFFFFF),
  );

  static const dark = AppPalette._(
    background: Color(0xFF101010),
    surface: Color(0xFF1A1A1A),
    raised: Color(0xFF242424),
    ink: Color(0xFFF4F4F4),
    muted: Color(0xFFB8B8B8),
    border: Color(0xFF414141),
    positive: Color(0xFFF0F0F0),
    negative: Color(0xFFBEBEBE),
    warning: Color(0xFFB0B0B0),
    onStrong: Color(0xFF101010),
  );

  final Color background;
  final Color surface;
  final Color raised;
  final Color ink;
  final Color muted;
  final Color border;
  final Color positive;
  final Color negative;
  final Color warning;
  final Color onStrong;
}

class AppTokens {
  AppTokens._();

  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 24.0;
  static const space6 = 32.0;
  static const minimumTouchTarget = 48.0;

  static const radiusSmall = 8.0;
  static const radiusMedium = 12.0;
  static const radiusLarge = 16.0;

  static const motionShort = Duration(milliseconds: 140);
  static const motionStandard = Duration(milliseconds: 220);
}

class AppTheme {
  AppTheme._();

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final palette = AppPalette.forBrightness(brightness == Brightness.dark);
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.ink,
      onPrimary: palette.onStrong,
      primaryContainer: isDark
          ? const Color(0xFF333333)
          : const Color(0xFFE8E8E8),
      onPrimaryContainer: palette.ink,
      primaryFixed: const Color(0xFFD8D8D8),
      primaryFixedDim: const Color(0xFFC0C0C0),
      onPrimaryFixed: const Color(0xFF161616),
      onPrimaryFixedVariant: const Color(0xFF424242),
      secondary: palette.muted,
      onSecondary: isDark ? const Color(0xFF101010) : Colors.white,
      secondaryContainer: isDark
          ? const Color(0xFF303030)
          : const Color(0xFFECECEC),
      onSecondaryContainer: palette.ink,
      secondaryFixed: const Color(0xFFE2E2E2),
      secondaryFixedDim: const Color(0xFFC9C9C9),
      onSecondaryFixed: const Color(0xFF191919),
      onSecondaryFixedVariant: const Color(0xFF484848),
      tertiary: palette.negative,
      onTertiary: isDark ? const Color(0xFF101010) : Colors.white,
      tertiaryContainer: isDark
          ? const Color(0xFF353535)
          : const Color(0xFFE8E8E8),
      onTertiaryContainer: palette.ink,
      tertiaryFixed: const Color(0xFFE5E5E5),
      tertiaryFixedDim: const Color(0xFFCCCCCC),
      onTertiaryFixed: const Color(0xFF191919),
      onTertiaryFixedVariant: const Color(0xFF484848),
      error: palette.negative,
      onError: isDark ? const Color(0xFF101010) : Colors.white,
      errorContainer: isDark
          ? const Color(0xFF3A3A3A)
          : const Color(0xFFE7E7E7),
      onErrorContainer: palette.ink,
      surface: palette.background,
      onSurface: palette.ink,
      onSurfaceVariant: palette.muted,
      outline: isDark ? const Color(0xFF8A8A8A) : const Color(0xFF737373),
      outlineVariant: palette.border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isDark
          ? const Color(0xFFECECEC)
          : const Color(0xFF262626),
      onInverseSurface: isDark ? const Color(0xFF171717) : Colors.white,
      inversePrimary: isDark
          ? const Color(0xFF252525)
          : const Color(0xFFD0D0D0),
      surfaceTint: palette.ink,
      surfaceContainerLowest: isDark ? const Color(0xFF0B0B0B) : Colors.white,
      surfaceContainerLow: isDark
          ? const Color(0xFF141414)
          : const Color(0xFFFAFAFA),
      surfaceContainer: palette.surface,
      surfaceContainerHigh: isDark
          ? const Color(0xFF202020)
          : const Color(0xFFF0F0F0),
      surfaceContainerHighest: palette.raised,
      surfaceDim: isDark ? const Color(0xFF101010) : const Color(0xFFE4E4E4),
      surfaceBright: isDark ? const Color(0xFF2B2B2B) : Colors.white,
    );
    final baseTextTheme = (isDark ? ThemeData.dark() : ThemeData.light())
        .textTheme
        .apply(bodyColor: palette.ink, displayColor: palette.ink);

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      textTheme: _withTabularFigures(baseTextTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.ink,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: palette.raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
          side: BorderSide(color: palette.border),
        ),
        margin: const EdgeInsets.all(AppTokens.space2),
      ),
      dividerTheme: DividerThemeData(color: palette.border, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space4,
          vertical: AppTokens.space3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
          borderSide: BorderSide(color: palette.ink, width: 1.5),
        ),
        labelStyle: TextStyle(color: palette.muted),
        hintStyle: TextStyle(color: palette.muted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(
            AppTokens.minimumTouchTarget,
            AppTokens.minimumTouchTarget,
          ),
          backgroundColor: palette.ink,
          foregroundColor: palette.onStrong,
          disabledBackgroundColor: isDark
              ? const Color(0xFF414141)
              : const Color(0xFFE0E0E0),
          disabledForegroundColor: palette.muted,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(
            AppTokens.minimumTouchTarget,
            AppTokens.minimumTouchTarget,
          ),
          backgroundColor: palette.ink,
          foregroundColor: palette.onStrong,
          disabledBackgroundColor: isDark
              ? const Color(0xFF414141)
              : const Color(0xFFE0E0E0),
          disabledForegroundColor: palette.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            AppTokens.minimumTouchTarget,
            AppTokens.minimumTouchTarget,
          ),
          foregroundColor: palette.ink,
          disabledForegroundColor: palette.muted,
          side: BorderSide(color: palette.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            AppTokens.minimumTouchTarget,
            AppTokens.minimumTouchTarget,
          ),
          foregroundColor: palette.ink,
          disabledForegroundColor: palette.muted,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            AppTokens.minimumTouchTarget,
            AppTokens.minimumTouchTarget,
          ),
          foregroundColor: palette.ink,
          disabledForegroundColor: palette.muted,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLarge),
          side: BorderSide(color: palette.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.raised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusLarge),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
          side: BorderSide(color: palette.border),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return isDark ? const Color(0xFF414141) : const Color(0xFFE0E0E0);
          }
          return states.contains(WidgetState.selected) ? palette.ink : null;
        }),
        checkColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? (isDark ? Colors.white : palette.ink)
              : palette.onStrong,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? (isDark ? const Color(0xFF929292) : const Color(0xFF707070))
              : states.contains(WidgetState.selected)
              ? palette.ink
              : palette.muted,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (states.contains(WidgetState.disabled)
                    ? palette.muted
                    : palette.onStrong)
              : palette.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return isDark ? const Color(0xFF414141) : const Color(0xFFE0E0E0);
          }
          return states.contains(WidgetState.selected)
              ? palette.ink
              : palette.border;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.ink,
        linearTrackColor: palette.border,
        circularTrackColor: palette.border,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.ink,
        contentTextStyle: TextStyle(color: palette.onStrong),
        behavior: SnackBarBehavior.floating,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: palette.ink,
        unselectedLabelColor: palette.muted,
        indicatorColor: palette.ink,
        dividerColor: palette.border,
      ),
    );
  }

  static TextTheme _withTabularFigures(TextTheme theme) {
    TextStyle? tabular(TextStyle? style) =>
        style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    return theme.copyWith(
      displayLarge: tabular(theme.displayLarge),
      displayMedium: tabular(theme.displayMedium),
      displaySmall: tabular(theme.displaySmall),
      headlineLarge: tabular(theme.headlineLarge),
      headlineMedium: tabular(theme.headlineMedium),
      headlineSmall: tabular(theme.headlineSmall),
      titleLarge: tabular(theme.titleLarge),
      titleMedium: tabular(theme.titleMedium),
      titleSmall: tabular(theme.titleSmall),
      bodyLarge: tabular(theme.bodyLarge),
      bodyMedium: tabular(theme.bodyMedium),
      bodySmall: tabular(theme.bodySmall),
      labelLarge: tabular(theme.labelLarge),
      labelMedium: tabular(theme.labelMedium),
      labelSmall: tabular(theme.labelSmall),
    );
  }
}
