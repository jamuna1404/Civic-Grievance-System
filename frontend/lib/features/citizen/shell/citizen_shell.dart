import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../complaints/presentation/photo_step_screen.dart';
import '../complaints/presentation/track_complaints_screen.dart';
import '../profile/profile_screen.dart';

/// The currently selected shell tab (0=Track, 1=Register, 2=Profile). Exposed
/// as a provider so any screen can switch tabs (e.g. the Track empty state
/// jumping to Register).
class CitizenTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final citizenTabProvider =
    NotifierProvider<CitizenTabNotifier, int>(CitizenTabNotifier.new);

/// Index of the Register (primary action) destination.
const int kRegisterTabIndex = 1;

/// The signed-in citizen's main navigation shell.
///
/// Responsive: a bottom [NavigationBar] on narrow (phone) layouts, switching to
/// a side [NavigationRail] on wide (tablet/desktop) layouts. The middle
/// destination — Register Complaint — is emphasized as the primary action in
/// both layouts.
class CitizenShell extends ConsumerWidget {
  const CitizenShell({super.key});

  static const _railBreakpoint = 720.0;

  static const _screens = [
    TrackComplaintsScreen(),
    PhotoStepScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(citizenTabProvider);
    void onSelect(int i) => ref.read(citizenTabProvider.notifier).select(i);

    final body = IndexedStack(index: index, children: _screens);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _railBreakpoint) {
          return Scaffold(
            body: Row(
              children: [
                _CitizenRail(selected: index, onSelect: onSelect),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: onSelect,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Track',
              ),
              NavigationDestination(
                icon: _EmphasizedAddIcon(active: index == kRegisterTabIndex),
                label: 'Register',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Side rail used on wide layouts. Register is surfaced as a raised primary
/// button above the standard destinations.
class _CitizenRail extends StatelessWidget {
  const _CitizenRail({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selected,
      onDestinationSelected: onSelect,
      labelType: NavigationRailLabelType.all,
      groupAlignment: -0.85,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: FloatingActionButton(
          heroTag: 'register-fab',
          elevation: 1,
          onPressed: () => onSelect(kRegisterTabIndex),
          tooltip: 'Register Complaint',
          child: const Icon(Icons.add),
        ),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: Text('Track'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.add_circle_outline),
          selectedIcon: Icon(Icons.add_circle),
          label: Text('Register'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: Text('Profile'),
        ),
      ],
    );
  }
}

/// The center destination's icon: a filled primary "pill" so Register reads as
/// the app's primary action rather than a peer of the other tabs.
class _EmphasizedAddIcon extends StatelessWidget {
  const _EmphasizedAddIcon({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 32,
      decoration: BoxDecoration(
        color: active ? scheme.primary : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(
        Icons.add,
        size: 22,
        color: active ? scheme.onPrimary : scheme.onPrimaryContainer,
      ),
    );
  }
}
