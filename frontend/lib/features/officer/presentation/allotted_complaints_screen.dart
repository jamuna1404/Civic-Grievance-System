import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_buttons.dart';
import '../data/officer_work_repository.dart';
import 'officer_complaint_detail_screen.dart';
import 'widgets/officer_complaint_card.dart';

/// Allotted tab — open complaints assigned to this officer.
class AllottedComplaintsScreen extends ConsumerWidget {
  const AllottedComplaintsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allottedComplaintsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Allotted Complaints')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(allottedComplaintsProvider.future),
        child: async.when(
          loading: () => const _AllottedComplaintsSkeleton(),
          error: (err, _) => _CenteredMessage(
            icon: Icons.cloud_off_outlined,
            message: err is ApiException
                ? err.message
                : 'Couldn’t load your complaints.',
            action: SecondaryButton(
              label: 'Retry',
              icon: Icons.refresh,
              expand: false,
              onPressed: () => ref.invalidate(allottedComplaintsProvider),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const _CenteredMessage(
                icon: Icons.inbox_outlined,
                message: 'No open complaints assigned to you right now.',
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) => OfficerComplaintCard(
                complaint: items[i],
                onTap: () => context.push(
                  AppRoutes.officerComplaintDetail,
                  extra: OfficerComplaintArgs(
                    complaint: items[i],
                    canUpdateStatus: true,
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

class _AllottedComplaintsSkeleton extends StatefulWidget {
  const _AllottedComplaintsSkeleton();

  @override
  State<_AllottedComplaintsSkeleton> createState() =>
      _AllottedComplaintsSkeletonState();
}

class _AllottedComplaintsSkeletonState
    extends State<_AllottedComplaintsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;

    return FadeTransition(
      opacity: _controller.drive(Tween<double>(begin: 0.4, end: 0.8)),
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) => Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: baseColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    width: 120,
                    height: 16,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 80,
                    height: 24,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                height: 14,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: 200,
                height: 14,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: baseColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 60,
                    height: 12,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: baseColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 80,
                    height: 12,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
