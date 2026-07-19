import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Central [ThemeData] factory for CivicRoute.
///
/// Light mode derives from a seeded scheme; dark mode uses a hand-tuned scheme
/// with elevated neutral grays. Both share the same component styling so the
/// two modes feel like one design system, not two.
abstract final class AppTheme {
  const AppTheme._();

  // --- Color schemes -------------------------------------------------------

  static final ColorScheme _lightScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.seed,
        brightness: Brightness.light,
      ).copyWith(
        surface: AppColors.lightSurface,
        surfaceContainerLowest: AppColors.lightSurface,
        surfaceContainerLow: AppColors.lightBackground,
        surfaceContainer: AppColors.lightSurfaceAlt,
        outlineVariant: AppColors.lightBorder,
        secondary: AppColors.accentIndigo,
        error: AppColors.danger,
      );

  /// Hand-tuned dark scheme. Not `fromSeed(dark)` — surfaces are explicit
  /// layered grays so elevation reads without pure-black halation.
  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.darkPrimary,
    onPrimary: AppColors.darkOnPrimary,
    primaryContainer: Color(0xFF16413F),
    onPrimaryContainer: Color(0xFFB9EDE9),
    secondary: AppColors.darkSecondary,
    onSecondary: Color(0xFF141B33),
    secondaryContainer: Color(0xFF2C3550),
    onSecondaryContainer: Color(0xFFD9E1FF),
    tertiary: Color(0xFF9FB4C7),
    onTertiary: Color(0xFF102434),
    error: Color(0xFFE7897F),
    onError: Color(0xFF3A0906),
    errorContainer: Color(0xFF5C201A),
    onErrorContainer: Color(0xFFFFD9D3),
    surface: AppColors.darkSurface,
    onSurface: Color(0xFFE3E6E7),
    onSurfaceVariant: Color(0xFFAFB6B8),
    surfaceContainerLowest: AppColors.darkBackground,
    surfaceContainerLow: Color(0xFF1A1E20),
    surfaceContainer: AppColors.darkSurface,
    surfaceContainerHigh: AppColors.darkSurfaceAlt,
    surfaceContainerHighest: Color(0xFF2E3438),
    outline: Color(0xFF4A5155),
    outlineVariant: AppColors.darkBorder,
    inverseSurface: Color(0xFFE3E6E7),
    onInverseSurface: Color(0xFF1E2225),
    inversePrimary: AppColors.seed,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  // --- Public entry points -------------------------------------------------

  static ThemeData light() => _build(_lightScheme, AppColors.lightBackground);

  static ThemeData dark() => _build(_darkScheme, AppColors.darkBackground);

  // --- Shared component styling --------------------------------------------

  static ThemeData _build(ColorScheme scheme, Color scaffoldBackground) {
    final base = ThemeData(brightness: scheme.brightness, useMaterial3: true);
    final textTheme = AppTypography.buildTextTheme(base.textTheme);
    final isDark = scheme.brightness == Brightness.dark;

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
        ),
      ),

      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: isDark ? 0 : 1,
        shadowColor: isDark ? Colors.transparent : Colors.black.withValues(
          alpha: 0.06,
        ),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: AppSpacing.lg,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: textTheme.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          textStyle: textTheme.labelLarge,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: scheme.error),
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide(color: scheme.outline),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? AppColors.darkSurfaceAlt
            : AppColors.lightSurfaceAlt,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        labelStyle: textTheme.labelMedium,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
    );
  }
}
