import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../application/session_controller.dart';
import '../data/auth_repository.dart';
import 'widgets/auth_scaffold.dart';

/// Screen 3 — new users provide their full name. Single action: Continue.
///
/// Only reached when verify-otp reported `new_user: true`.
class NameScreen extends ConsumerStatefulWidget {
  const NameScreen({super.key, required this.phoneNumber});

  final String phoneNumber;

  @override
  ConsumerState<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends ConsumerState<NameScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  bool get _isValid => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_isValid || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = await ref
          .read(authRepositoryProvider)
          .completeSignup(widget.phoneNumber, _controller.text.trim());
      if (!mounted) return;
      // Session established — router redirects to home.
      await ref.read(sessionControllerProvider.notifier).signIn(
            token: session.sessionToken,
            fullName: session.fullName,
            phoneNumber: widget.phoneNumber,
            citizenId: session.citizenId,
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'What’s your name?',
      subtitle: 'This is how officers will see you on your complaints.',
      children: [
        AppTextField(
          controller: _controller,
          label: 'Full name',
          hintText: 'e.g. Priya Raman',
          prefixIcon: Icons.person_outline,
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: 'Continue',
          isLoading: _submitting,
          onPressed: _isValid ? _continue : null,
        ),
      ],
    );
  }
}
