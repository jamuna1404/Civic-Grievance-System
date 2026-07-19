import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../application/session_controller.dart';
import '../data/auth_repository.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/otp_input.dart';

/// Screen 2 — enter the 6-digit OTP. Single action: Verify.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phoneNumber});

  /// Canonical E.164 phone number the OTP was sent to.
  final String phoneNumber;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
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
          .read(authRepositoryProvider)
          .verifyOtp(widget.phoneNumber, _code);
      if (!mounted) return;

      if (result.newUser) {
        context.push(AppRoutes.name, extra: widget.phoneNumber);
      } else {
        // Returning user — session established, router redirects to home.
        await ref.read(sessionControllerProvider.notifier).signIn(
              token: result.sessionToken!,
              fullName: result.fullName!,
              phoneNumber: widget.phoneNumber,
              citizenId: result.citizenId!,
            );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
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
