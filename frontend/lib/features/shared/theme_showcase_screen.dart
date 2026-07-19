import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_text_field.dart';

/// Temporary review screen for the scaffolding milestone.
///
/// Shows the theme-mode toggle plus a sample of the core components (cards,
/// buttons, inputs, type scale, status chips) so both light and dark themes
/// can be visually verified before real features are built. This screen is
/// throwaway and will be replaced once auth/home screens land.
class ThemeShowcaseScreen extends ConsumerWidget {
  const ThemeShowcaseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CivicRoute'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Center(
              child: Text(
                'Design system',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _SectionLabel('Appearance'),
          _ThemeModeToggle(
            mode: mode,
            onChanged: (m) =>
                ref.read(themeModeProvider.notifier).setThemeMode(m),
          ),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel('Typography'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Headline — Sora', style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text('Title medium', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Body text set in Inter. CivicRoute helps Chennai residents '
                  'report civic issues and routes each complaint to the right '
                  'ward officer.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Caption / bodySmall',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel('Buttons'),
          AppCard(
            child: Column(
              children: [
                PrimaryButton(
                  label: 'File a complaint',
                  icon: Icons.add_location_alt_outlined,
                  onPressed: () {},
                ),
                const SizedBox(height: AppSpacing.md),
                SecondaryButton(
                  label: 'Track existing',
                  icon: Icons.search,
                  onPressed: () {},
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        label: 'Loading',
                        isLoading: true,
                        onPressed: () {},
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    TextButton(onPressed: () {}, child: const Text('Skip')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel('Status'),
          const AppCard(child: _StatusChipsRow()),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel('Input'),
          const AppCard(
            child: Column(
              children: [
                AppTextField(
                  label: 'Complaint title',
                  hintText: 'e.g. Overflowing bin on Anna Salai',
                  prefixIcon: Icons.edit_outlined,
                ),
                SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Describe the issue',
                  hintText: 'Add details…',
                  maxLines: 3,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _ThemeModeToggle extends StatelessWidget {
  const _ThemeModeToggle({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Theme mode',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
              selected: {mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onChanged(s.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChipsRow extends StatelessWidget {
  const _StatusChipsRow();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _StatusChip(label: 'Submitted', color: Color(0xFF3A6EA5)),
        _StatusChip(label: 'In progress', color: Color(0xFFB8860B)),
        _StatusChip(label: 'Resolved', color: Color(0xFF2E7D5B)),
        _StatusChip(label: 'Rejected', color: Color(0xFFC1443B)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
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
