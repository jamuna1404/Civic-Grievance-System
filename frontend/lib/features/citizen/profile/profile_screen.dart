import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../auth/application/session_controller.dart';
import 'data/citizen_repository.dart';

/// Profile & Settings — name (editable), phone (read-only), theme selector
/// (persisted to the backend), and logout.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _nameController;
  bool _savingName = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionControllerProvider);
    _nameController = TextEditingController(text: session?.fullName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveName(CitizenSession session) async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == session.fullName || _savingName) return;
    FocusScope.of(context).unfocus();
    setState(() => _savingName = true);
    try {
      final saved = await ref.read(citizenRepositoryProvider).updateName(
            token: session.token,
            fullName: newName,
          );
      await ref.read(sessionControllerProvider.notifier).updateName(saved);
      _snack('Name updated.');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changeTheme(CitizenSession session, ThemeMode mode) async {
    final previous = ref.read(themeModeProvider);
    if (mode == previous) return;
    // Apply locally right away for instant feedback…
    await ref.read(themeModeProvider.notifier).setThemeMode(mode);
    // …then sync to the server.
    try {
      await ref.read(citizenRepositoryProvider).updateThemeMode(
            token: session.token,
            mode: mode,
          );
    } on ApiException {
      _snack('Theme saved on this device, but couldn’t sync to your account.');
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You’ll need your phone number to sign back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(sessionControllerProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionControllerProvider);
    final themeMode = ref.watch(themeModeProvider);

    if (session == null) {
      // Logged out mid-frame; router will redirect momentarily.
      return const Scaffold(body: SizedBox.shrink());
    }

    // Rebuild Save enable-state as the field changes.
    final canSave = _nameController.text.trim().isNotEmpty &&
        _nameController.text.trim() != session.fullName;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _SectionLabel('Account'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTextField(
                      controller: _nameController,
                      label: 'Full name',
                      hintText: 'Your name',
                      prefixIcon: Icons.person_outline,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Align(
                      alignment: Alignment.centerRight,
                      child: PrimaryButton(
                        label: 'Save',
                        expand: false,
                        isLoading: _savingName,
                        onPressed: canSave ? () => _saveName(session) : null,
                      ),
                    ),
                    const Divider(),
                    Text('Phone number', style: theme.textTheme.labelLarge),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Text(session.phoneNumber, style: theme.textTheme.bodyLarge),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              _SectionLabel('Appearance'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Theme', style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Light'),
                            icon: Icon(Icons.light_mode_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Dark'),
                            icon: Icon(Icons.dark_mode_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('System'),
                            icon: Icon(Icons.brightness_auto_outlined),
                          ),
                        ],
                        selected: {themeMode},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => _changeTheme(session, s.first),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Log out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.md,
      ),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
