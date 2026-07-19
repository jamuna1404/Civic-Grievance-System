import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../citizen/complaints/data/complaint_status.dart';

/// The next forward move for a given status (label + target wire status).
({String label, String target})? _forwardAction(ComplaintStatus current) {
  switch (current) {
    case ComplaintStatus.submitted:
      return (label: 'Acknowledge', target: 'ACKNOWLEDGED');
    case ComplaintStatus.acknowledged:
      return (label: 'Start Progress', target: 'IN_PROGRESS');
    case ComplaintStatus.inProgress:
      return (label: 'Mark Resolved', target: 'RESOLVED');
    case ComplaintStatus.resolved:
    case ComplaintStatus.rejected:
      return null; // terminal
  }
}

/// Status-update control for the assigned officer: an optional remarks field
/// plus the single forward action (Acknowledge → Start Progress → Mark
/// Resolved) and a reject option. Hidden work once the complaint is terminal.
class StatusUpdateControl extends StatefulWidget {
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
  State<StatusUpdateControl> createState() => _StatusUpdateControlState();
}

class _StatusUpdateControlState extends State<StatusUpdateControl> {
  final _remarks = TextEditingController();

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forward = _forwardAction(widget.current);

    if (forward == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.lgAll,
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: 20, color: widget.current.color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'This complaint is ${widget.current.label.toLowerCase()}. '
                'No further action needed.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    final canReject = widget.current != ComplaintStatus.rejected;

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
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _remarks,
            minLines: 2,
            maxLines: 4,
            enabled: !widget.submitting,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Remarks (optional) — visible to the citizen',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: forward.label,
            icon: Icons.arrow_forward,
            isLoading: widget.submitting,
            onPressed: widget.submitting
                ? null
                : () => widget.onSubmit(forward.target, _remarks.text.trim()),
          ),
          if (canReject) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: widget.submitting
                  ? null
                  : () => widget.onSubmit('REJECTED', _remarks.text.trim()),
              icon: Icon(Icons.block, size: 18, color: theme.colorScheme.error),
              label: Text('Reject complaint',
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          ],
        ],
      ),
    );
  }
}
