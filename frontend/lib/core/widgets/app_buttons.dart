import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// An animated wrapper that scales its child down on touch down and back up
/// on touch release or cancel. Uses [Listener] so it doesn't interfere with
/// button ink ripples or gestures.
class AnimatedScaleButton extends StatefulWidget {
  const AnimatedScaleButton({
    super.key,
    required this.child,
    required this.enabled,
  });

  final Widget child;
  final bool enabled;

  @override
  State<AnimatedScaleButton> createState() => _AnimatedScaleButtonState();
}

class _AnimatedScaleButtonState extends State<AnimatedScaleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 85),
      lowerBound: 0.96,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return Listener(
      onPointerDown: (_) => _controller.animateTo(0.96, curve: Curves.easeInOut),
      onPointerUp: (_) => _controller.animateTo(1.0, curve: Curves.easeInOut),
      onPointerCancel: (_) => _controller.animateTo(1.0, curve: Curves.easeInOut),
      child: ScaleTransition(
        scale: _controller,
        child: widget.child,
      ),
    );
  }
}

/// Primary call-to-action button. Filled, full-width by default.
///
/// Shows a spinner and disables interaction while [isLoading] is true.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;

  /// Whether the button stretches to fill its horizontal constraints.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const _ButtonSpinner()
        : _ButtonContent(label: label, icon: icon);

    final button = AnimatedScaleButton(
      enabled: onPressed != null && !isLoading,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        child: child,
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Secondary action button. Outlined, lower emphasis than [PrimaryButton].
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = AnimatedScaleButton(
      enabled: onPressed != null,
      child: OutlinedButton(
        onPressed: onPressed,
        child: _ButtonContent(label: label, icon: icon),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (icon == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpacing.sm),
        // Flexible so a long label ellipsizes instead of overflowing when the
        // button is width-constrained.
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}
