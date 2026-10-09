import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_buttons.dart';
import '../data/officer_work_repository.dart';
import 'officer_complaint_detail_screen.dart';
import 'widgets/team_complaint_card.dart';

/// Manage Team tab — complaints assigned to this officer's subordinates.
/// Only ever shown to officers with subordinates (see OfficerShell); the
/// backend already sorts RESOLUTION_REQUESTED items first.
class TeamComplaintsScreen extends ConsumerWidget {
  const TeamComplaintsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(teamComplaintsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Team')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(teamComplaintsProvider.future),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _CenteredMessage(
            icon: Icons.cloud_off_outlined,
            message: err is ApiException
                ? err.message
                : 'Couldn’t load your team’s complaints.',
            action: SecondaryButton(
              label: 'Retry',
              icon: Icons.refresh,
              expand: false,
              onPressed: () => ref.invalidate(teamComplaintsProvider),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const _CenteredMessage(
                icon: Icons.groups_outlined,
                message: 'No complaints from your team right now.',
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) => TeamComplaintCard(
                complaint: items[i],
                onTap: () => context.push(
                  AppRoutes.officerComplaintDetail,
                  extra: OfficerComplaintArgs(
                    complaint: items[i],
                    canUpdateStatus: false,
                    canReview: true,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(message,
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        ),
        if (action != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Center(child: action!),
        ],
      ],
    );
  }
}
