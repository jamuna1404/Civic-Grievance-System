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

/// Track tab — every complaint in this officer's jurisdiction area (any
/// status), for reference. Read-only: no status control on the detail.
class OfficerTrackScreen extends ConsumerWidget {
  const OfficerTrackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(officerTrackProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Track Complaints')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(officerTrackProvider.future),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 120),
              Icon(Icons.cloud_off_outlined,
                  size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Text(
                  err is ApiException ? err.message : 'Couldn’t load complaints.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: SecondaryButton(
                  label: 'Retry',
                  icon: Icons.refresh,
                  expand: false,
                  onPressed: () => ref.invalidate(officerTrackProvider),
                ),
              ),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.map_outlined,
                      size: 48, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: AppSpacing.lg),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                    child: Text(
                      'No complaints in your jurisdiction area yet.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
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
                    canUpdateStatus: false,
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
