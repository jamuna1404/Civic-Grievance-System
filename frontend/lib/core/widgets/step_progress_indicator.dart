import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A themed "Step X of N" header: a small label plus a segmented bar where
/// completed and current steps are filled with the primary color.
class StepProgressIndicator extends StatelessWidget {
  const StepProgressIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    this.label,
  });

  /// 1-based index of the active step.
  final int currentStep;
  final int totalSteps;

  /// Optional short caption for the current step (e.g. "Photo").
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Step $currentStep of $totalSteps',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            if (label != null)
              Text(
                label!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: List.generate(totalSteps, (i) {
            final done = i < currentStep;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: i == totalSteps - 1 ? 0 : AppSpacing.sm,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 6,
                  decoration: BoxDecoration(
                    color: done ? scheme.primary : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
