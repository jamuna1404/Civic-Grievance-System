import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../citizen/auth/presentation/widgets/auth_scaffold.dart';
import '../data/officer_repository.dart';

/// Officer login — phone entry, then dummy OTP. Enrollment is a separate path
/// linked from here.
class OfficerLoginScreen extends ConsumerStatefulWidget {
  const OfficerLoginScreen({super.key});

  @override
  ConsumerState<OfficerLoginScreen> createState() => _OfficerLoginScreenState();
}

class _OfficerLoginScreenState extends ConsumerState<OfficerLoginScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  bool get _isValid => _controller.text.length == 10;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_isValid || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final phone =
          await ref.read(officerRepositoryProvider).sendOtp(_controller.text);
      if (!mounted) return;
      context.push(AppRoutes.officerOtp, extra: phone);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AuthScaffold(
      showBack: false,
      title: 'Officer sign in',
      subtitle: 'Enter your registered mobile number to receive a code.',
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 10,
          style: theme.textTheme.titleLarge,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _sendOtp(),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: InputDecoration(
            counterText: '',
            hintText: '98765 43210',
            errorText: _error,
            prefixIcon: Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.sm,
              ),
              child: Center(
                widthFactor: 1,
                child: Text('+91', style: theme.textTheme.titleLarge),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: 'Send OTP',
          isLoading: _submitting,
          onPressed: _isValid ? _sendOtp : null,
        ),
        const SizedBox(height: AppSpacing.xl),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'New officer?',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          label: 'Enroll as an officer',
          icon: Icons.badge_outlined,
          onPressed: () => context.push(AppRoutes.officerEnroll),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton(
            onPressed: () => context.go(AppRoutes.role),
            child: const Text('Choose a different role'),
          ),
        ),
      ],
    );
  }
}
