import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../citizen/complaints/data/complaint_models.dart';
import '../../../citizen/complaints/data/complaint_status.dart';

/// List card for the manager's Team Complaints tab. Shows which subordinate
/// it's assigned to (name + designation — an officer's identity, not a
/// citizen's, so this is fine to show), department, status, and a preview.
/// RESOLUTION_REQUESTED items render as a highlighted card with an
/// "Action Needed" badge so they stand out from the rest of the list.
class TeamComplaintCard extends StatelessWidget {
  const TeamComplaintCard({
    super.key,
    required this.complaint,
    required this.onTap,
  });

  final ComplaintSummary complaint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final status = ComplaintStatus.fromWire(complaint.status);
    final dept = complaint.department;
    final needsAction = status == ComplaintStatus.resolutionRequested;

    // Highlight fill needs a touch more presence on a dark surface to read as
    // "highlighted"; the solid border + badge carry the emphasis in both.
    final highlightFill = status.color.withValues(alpha: isDark ? 0.16 : 0.09);

    return Material(
      color: needsAction ? highlightFill : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: needsAction
                  ? status.color.withValues(alpha: 0.6)
                  : theme.colorScheme.outlineVariant,
              width: needsAction ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (needsAction) ...[
                _ActionNeededBadge(color: status.color),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: [
                  Icon(dept.icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(dept.label,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis),
                  ),
                  StatusChip(status: status, dense: true),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                complaint.descriptionText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  if (complaint.officerName != null) ...[
                    Icon(Icons.badge_outlined,
                        size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        complaint.officerDesignationName != null
                            ? '${complaint.officerName} · ${complaint.officerDesignationName}'
                            : complaint.officerName!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Icon(Icons.schedule,
                      size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    relativeTime(complaint.createdAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionNeededBadge extends StatelessWidget {
  const _ActionNeededBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.priority_high, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            'ACTION NEEDED',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
