import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';

/// A manager's decision on a subordinate's closure request: approve & close,
/// or send back for rework (remarks required — the subordinate needs to
/// know what's still missing).
class ReviewControl extends StatelessWidget {
  const ReviewControl({
    super.key,
    required this.submitting,
    required this.onDecide,
  });

  final bool submitting;

  /// Called with the decision ('APPROVE' | 'SEND_BACK') and trimmed remarks.
  final void Function(String decision, String remarks) onDecide;

  Future<void> _sendBack(BuildContext context) async {
    final controller = TextEditingController();
    final remarks = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send back for rework'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What\'s still needed?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.of(dialogContext).pop(controller.text);
            },
            child: const Text('Send back'),
          ),
        ],
      ),
    );
    if (remarks == null || remarks.trim().isEmpty) return; // cancelled
    onDecide('SEND_BACK', remarks.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text('Review closure request', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Approve & Close',
            icon: Icons.check_circle_outline,
            isLoading: submitting,
            onPressed:
                submitting ? null : () => onDecide('APPROVE', ''),
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: 'Send Back for Rework',
            icon: Icons.undo,
            onPressed: submitting ? null : () => _sendBack(context),
          ),
        ],
      ),
    );
  }
}
