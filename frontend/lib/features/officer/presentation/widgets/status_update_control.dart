import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../citizen/complaints/data/complaint_status.dart';

/// The single valid next move for a given status (label + target wire
/// status). Officers get exactly one forward action, never a free choice —
/// RESOLUTION_REQUESTED, RESOLVED, and REJECTED have none: the first is
/// awaiting a supervisor, the other two are terminal.
({String label, String target})? _forwardAction(ComplaintStatus current) {
  switch (current) {
    case ComplaintStatus.submitted:
      return (label: 'Acknowledge', target: 'ACKNOWLEDGED');
    case ComplaintStatus.acknowledged:
      return (label: 'Start Work', target: 'IN_PROGRESS');
    case ComplaintStatus.inProgress:
      return (label: 'Request Closure', target: 'RESOLUTION_REQUESTED');
    case ComplaintStatus.resolutionRequested:
    case ComplaintStatus.resolved:
    case ComplaintStatus.rejected:
      return null;
  }
}

/// Status-update control for the assigned officer: shows only the one valid
/// next action for the current status. Moving to RESOLUTION_REQUESTED opens
/// a confirmation dialog asking for optional remarks first. Every other
/// status (awaiting review, resolved, rejected) shows a read-only banner
/// instead of a button — the officer cannot self-approve or skip a step.
class StatusUpdateControl extends StatelessWidget {
  const StatusUpdateControl({
    super.key,
    required this.current,
    required this.submitting,
    required this.onSubmit,
  });

  final ComplaintStatus current;
  final bool submitting;

  /// Called with the target wire status and trimmed remarks (may be empty).
  final void Function(String newStatus, String remarks) onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forward = _forwardAction(current);

    if (current == ComplaintStatus.resolutionRequested) {
      return _Banner(
        icon: Icons.hourglass_top_outlined,
        color: current.color,
        message: 'Submitted for review — awaiting supervisor approval. '
            'You can’t act on this complaint until it’s reviewed.',
      );
    }

    if (forward == null) {
      return _Banner(
        icon: Icons.check_circle_outline,
        color: current.color,
        message: 'This complaint is ${current.label.toLowerCase()}. '
            'No further action needed.',
      );
    }

    final isClosureRequest = forward.target == 'RESOLUTION_REQUESTED';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Update status', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: forward.label,
            icon: Icons.arrow_forward,
            isLoading: submitting,
            onPressed: submitting
                ? null
                : () async {
                    if (isClosureRequest) {
                      final remarks = await _showClosureDialog(context);
                      if (remarks == null) return; // dialog was cancelled
                      onSubmit(forward.target, remarks.trim());
                    } else {
                      onSubmit(forward.target, '');
                    }
                  },
          ),
        ],
      ),
    );
  }

  /// Returns the entered remarks (may be empty) if confirmed, or null if the
  /// officer cancelled.
  Future<String?> _showClosureDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request closure'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What was done to resolve this? (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Submit for review'),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
