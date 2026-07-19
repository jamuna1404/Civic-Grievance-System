import 'package:flutter/material.dart';

/// Brand + semantic color palette for CivicRoute.
///
/// The accent is a deep, muted teal — reads as civic/government but modern,
/// deliberately steering away from the generic Material blue.
///
/// The dark palette is hand-tuned (not an inversion of light): dark surfaces
/// use layered neutral grays rather than pure black, so text edges don't
/// halate on OLED screens and elevation reads through subtle surface shifts.
abstract final class AppColors {
  const AppColors._();

  // --- Brand ---------------------------------------------------------------

  /// Seed for the light [ColorScheme]. Deep teal.
  static const Color seed = Color(0xFF0E6E6B);

  /// Secondary civic accent — a muted slate-indigo, used sparingly for
  /// informational emphasis.
  static const Color accentIndigo = Color(0xFF4B5D8A);

  // --- Shared semantic ------------------------------------------------------

  static const Color success = Color(0xFF2E7D5B);
  static const Color warning = Color(0xFFB8860B);
  static const Color danger = Color(0xFFC1443B);
  static const Color info = Color(0xFF3A6EA5);

  // --- Light neutrals -------------------------------------------------------

  static const Color lightBackground = Color(0xFFF6F7F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEEF1F1);
  static const Color lightBorder = Color(0xFFDCE0E0);

  // --- Dark neutrals (elevated grays, not pure black) -----------------------

  /// App background — a very dark neutral, still clearly not #000.
  static const Color darkBackground = Color(0xFF15181A);

  /// Base surface (cards, sheets) sits one step above the background.
  static const Color darkSurface = Color(0xFF1E2225);

  /// A more elevated surface for nested / raised content.
  static const Color darkSurfaceAlt = Color(0xFF262B2F);

  static const Color darkBorder = Color(0xFF343A3E);

  // Teal tuned for dark backgrounds — lighter & slightly desaturated so it
  // stays legible without glowing.
  static const Color darkPrimary = Color(0xFF5BC4BF);
  static const Color darkOnPrimary = Color(0xFF00312F);
  static const Color darkSecondary = Color(0xFF9AA9D6);
}
