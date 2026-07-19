import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../application/officer_session_controller.dart';
import '../data/officer_work_repository.dart';

/// Officer Profile — read-only identity fields, theme toggle (persisted to
/// user_preferences as OFFICER), and logout.
class OfficerProfileScreen extends ConsumerWidget {
  const OfficerProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(officerProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: profile.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  err is ApiException ? err.message : 'Couldn’t load your profile.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (p) => ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _Header(name: p.fullName, status: p.status),
                const SizedBox(height: AppSpacing.xl),
                _SectionLabel('Posting'),
                _InfoCard(rows: [
                  ('Department', p.departmentName),
                  ('Designation', p.designationName),
                  ('Jurisdiction', p.jurisdictionName),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _SectionLabel('Contact'),
                _InfoCard(rows: [
                  ('Phone', p.phone),
                  if (p.email != null && p.email!.isNotEmpty) ('Email', p.email!),
                  if (p.employeeId != null && p.employeeId!.isNotEmpty)
                    ('Employee ID', p.employeeId!),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _SectionLabel('Appearance'),
                const _ThemeCard(),
                const SizedBox(height: AppSpacing.xl),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(officerSessionProvider.notifier).signOut(),
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
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.status});

  final String name;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = status == 'PENDING_VERIFICATION';
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(Icons.badge_outlined,
              color: theme.colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: (pending
                          ? const Color(0xFFB8860B)
                          : const Color(0xFF2E7D5B))
                      .withValues(alpha: 0.14),
                  borderRadius: AppRadius.smAll,
                ),
                child: Text(
                  pending ? 'Pending verification' : 'Active',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<(String, String)> rows;

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
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(rows[i].$1,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ),
                Expanded(
                  child: Text(rows[i].$2, style: theme.textTheme.bodyLarge),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeCard extends ConsumerWidget {
  const _ThemeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);

    Future<void> change(ThemeMode m) async {
      if (m == mode) return;
      await ref.read(themeModeProvider.notifier).setThemeMode(m);
      final session = ref.read(officerSessionProvider);
      if (session == null) return;
      try {
        await ref
            .read(officerWorkRepositoryProvider)
            .updateThemeMode(token: session.token, mode: m);
      } on ApiException {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
              content: Text('Theme saved on device, but couldn’t sync.'),
            ));
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
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
                    icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined)),
                ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.brightness_auto_outlined)),
              ],
              selected: {mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => change(s.first),
            ),
          ),
        ],
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
      padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.md),
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
