import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A padded surface card with the app's standard radius and border.
///
/// Wraps [Card] so screens don't re-specify padding/shape each time. When
/// [onTap] is provided the whole card becomes tappable with an ink ripple.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}
