import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../data/auth_repository.dart';
import 'widgets/auth_scaffold.dart';

/// Screen 1 — enter a 10-digit Indian mobile number. The `+91` prefix is shown
/// but not editable. Single action: Send OTP.
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
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
      final phone = await ref
          .read(authRepositoryProvider)
          .sendOtp(_controller.text);
      if (!mounted) return;
      context.push(AppRoutes.otp, extra: phone);
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
      showBack: false,
      title: 'Enter your mobile number',
      subtitle: 'We’ll send you a 6-digit code to verify it.',
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('+91', style: theme.textTheme.titleLarge),
                ],
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
      ],
    );
  }
}
