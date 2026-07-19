import 'package:flutter/widgets.dart';

/// Design tokens for spacing, built on an 8px grid.
///
/// Use these instead of magic numbers so layout rhythm stays consistent
/// across the whole app.
abstract final class AppSpacing {
  const AppSpacing._();

  /// 4px — hairline gaps (icon ↔ label).
  static const double xs = 4;

  /// 8px — base unit.
  static const double sm = 8;

  /// 12px — tight internal padding.
  static const double md = 12;

  /// 16px — default content padding / gutter.
  static const double lg = 16;

  /// 24px — section spacing.
  static const double xl = 24;

  /// 32px — large section spacing.
  static const double xxl = 32;

  /// 48px — screen-level breathing room.
  static const double xxxl = 48;
}

/// Corner radius tokens. Cards sit at 12–16px; controls a touch tighter.
abstract final class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
}

/// Standard screen edge padding.
const EdgeInsets kScreenPadding = EdgeInsets.all(AppSpacing.lg);
