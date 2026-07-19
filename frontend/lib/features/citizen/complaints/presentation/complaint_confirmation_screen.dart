import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../shell/citizen_shell.dart';
import '../data/track_repository.dart';

/// Arguments passed to the confirmation screen via go_router `extra`.
class ComplaintConfirmationArgs {
  const ComplaintConfirmationArgs({
    required this.complaintId,
    this.unassigned = false,
  });

  final String complaintId;
  final bool unassigned;
}

/// Shown after a successful submission: confirms registration, shows the
/// complaint ID, and offers a shortcut to tracking.
class ComplaintConfirmationScreen extends ConsumerWidget {
  const ComplaintConfirmationScreen({super.key, required this.args});

  final ComplaintConfirmationArgs args;

  /// Refresh the list, switch to the Track tab, then return to the shell.
  void _goToTrack(BuildContext context, WidgetRef ref) {
    ref.invalidate(myComplaintsProvider);
    ref.read(citizenTabProvider.notifier).select(0);
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final shortId = args.complaintId.split('-').first.toUpperCase();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primaryContainer,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 52,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Complaint Registered',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    args.unassigned
                        ? 'Your complaint has been recorded. We’re still '
                            'matching it to an officer for your area.'
                        : 'Your complaint has been recorded and routed to the '
                            'responsible officer for your area.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _ComplaintIdCard(
                    fullId: args.complaintId,
                    shortId: shortId,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Track this complaint',
                    icon: Icons.timeline_outlined,
                    onPressed: () => _goToTrack(context, ref),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => _goToTrack(context, ref),
                    child: const Text('Back to home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComplaintIdCard extends StatelessWidget {
  const _ComplaintIdCard({required this.fullId, required this.shortId});

  final String fullId;
  final String shortId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(
        children: [
          Text(
            'COMPLAINT ID',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('#$shortId', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  fullId,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: fullId));
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(content: Text('Complaint ID copied')),
                    );
                },
                icon: const Icon(Icons.copy, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
