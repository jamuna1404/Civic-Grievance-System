import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../citizen/auth/presentation/widgets/auth_scaffold.dart';
import '../../citizen/auth/presentation/widgets/otp_input.dart';
import '../application/officer_session_controller.dart';
import '../data/officer_repository.dart';

/// Officer OTP verification. On success, either logs in (existing officer) or
/// prompts the caller to enroll (no officer record for that number).
class OfficerOtpScreen extends ConsumerStatefulWidget {
  const OfficerOtpScreen({super.key, required this.phoneNumber});

  final String phoneNumber;

  @override
  ConsumerState<OfficerOtpScreen> createState() => _OfficerOtpScreenState();
}

class _OfficerOtpScreenState extends ConsumerState<OfficerOtpScreen> {
  String _code = '';
  bool _submitting = false;
  String? _error;

  bool get _isComplete => _code.length == 6;

  Future<void> _verify() async {
    if (!_isComplete || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(officerRepositoryProvider)
          .verifyOtp(widget.phoneNumber, _code);
      if (!mounted) return;

      if (result.newUser) {
        _showEnrollPrompt();
      } else {
        await ref.read(officerSessionProvider.notifier).signIn(
              token: result.sessionToken!,
              fullName: result.fullName!,
              officerId: result.officerId!,
              status: result.status!,
              managesTeam: result.managesTeam,
            );
        // Router redirects to officer home.
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showEnrollPrompt() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('No officer account found'),
        content: const Text(
          'This number isn’t registered as an officer yet. Would you like to '
          'enroll?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.go(AppRoutes.officerEnroll);
            },
            child: const Text('Enroll'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AuthScaffold(
      title: 'Enter the 6-digit code',
      subtitle: 'Sent to ${widget.phoneNumber}',
      children: [
        OtpInput(
          hasError: _error != null,
          onChanged: (v) => setState(() {
            _code = v;
            _error = null;
          }),
          onCompleted: (_) => _verify(),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _error!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: 'Verify',
          isLoading: _submitting,
          onPressed: _isComplete ? _verify : null,
        ),
      ],
    );
  }
}
