import 'package:flutter/material.dart';

/// Canonical complaint statuses and their presentation.
///
/// Colors are chosen to stay distinct and readable on both light and dark
/// surfaces; chips render them as a translucent fill + solid dot + label so the
/// same hue works against either theme background.
enum ComplaintStatus {
  submitted('SUBMITTED', 'Submitted', Color(0xFF3A6EA5)), // blue
  acknowledged('ACKNOWLEDGED', 'Acknowledged', Color(0xFF6E56CF)), // violet
  inProgress('IN_PROGRESS', 'In progress', Color(0xFFC77700)), // amber
  resolutionRequested(
    'RESOLUTION_REQUESTED', 'Awaiting approval', Color(0xFF1C7C9C),
  ), // teal
  resolved('RESOLVED', 'Resolved', Color(0xFF2E7D5B)), // green
  rejected('REJECTED', 'Rejected', Color(0xFFC1443B)); // red

  const ComplaintStatus(this.wire, this.label, this.color);

  /// Backend enum value (`complaints.status`).
  final String wire;
  final String label;
  final Color color;

  static ComplaintStatus fromWire(String value) {
    return ComplaintStatus.values.firstWhere(
      (s) => s.wire == value,
      orElse: () => ComplaintStatus.submitted,
    );
  }

  /// The forward progression a non-rejected complaint moves through.
  static const progression = [
    ComplaintStatus.submitted,
    ComplaintStatus.acknowledged,
    ComplaintStatus.inProgress,
    ComplaintStatus.resolutionRequested,
    ComplaintStatus.resolved,
  ];
}

/// A compact colored status chip.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.dense = false});

  final ComplaintStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: status.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: status.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: (dense
                    ? theme.textTheme.labelSmall
                    : theme.textTheme.labelMedium)
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
