import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Type scale for CivicRoute.
///
/// Pairing:
///  - Headings: **Sora** — a geometric sans with a confident, institutional
///    feel for titles and numbers.
///  - Body / UI: **Inter** — a humanist sans tuned for screen legibility at
///    small sizes.
///
/// [buildTextTheme] returns a [TextTheme] whose colors are left to the theme
/// (they resolve against the active [ColorScheme]); only sizes, weights, and
/// families are fixed here.
abstract final class AppTypography {
  const AppTypography._();

  static TextTheme buildTextTheme(TextTheme base) {
    final heading = GoogleFonts.soraTextTheme(base);
    final body = GoogleFonts.interTextTheme(base);

    return base.copyWith(
      // Display & headline → Sora
      displayLarge: heading.displayLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      displayMedium: heading.displayMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      displaySmall: heading.displaySmall?.copyWith(fontWeight: FontWeight.w600),
      headlineLarge: heading.headlineLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.25,
      ),
      headlineMedium: heading.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: heading.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleLarge: heading.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
      ),
      // Titles (smaller) & body & labels → Inter
      titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: body.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: body.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: body.bodyMedium?.copyWith(height: 1.5),
      bodySmall: body.bodySmall?.copyWith(height: 1.45),
      labelLarge: body.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: body.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: body.labelSmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
