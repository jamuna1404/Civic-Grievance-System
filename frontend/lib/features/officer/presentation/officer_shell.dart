import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'allotted_complaints_screen.dart';
import 'officer_profile_screen.dart';
import 'officer_track_screen.dart';

/// Selected officer-shell tab (0=Allotted, 1=Track, 2=Profile).
final officerTabProvider = NotifierProvider<_OfficerTabNotifier, int>(
  _OfficerTabNotifier.new,
);

class _OfficerTabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void select(int index) => state = index;
}

/// Officer main navigation shell — same responsive pattern as the citizen app
/// (bottom bar on phones, side rail on wide layouts), 3 destinations.
class OfficerShell extends ConsumerWidget {
  const OfficerShell({super.key});

  static const _railBreakpoint = 720.0;

  static const _screens = [
    AllottedComplaintsScreen(),
    OfficerTrackScreen(),
    OfficerProfileScreen(),
  ];

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.assignment_outlined),
      selectedIcon: Icon(Icons.assignment),
      label: 'Allotted',
    ),
    NavigationDestination(
      icon: Icon(Icons.map_outlined),
      selectedIcon: Icon(Icons.map),
      label: 'Track',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(officerTabProvider);
    void onSelect(int i) => ref.read(officerTabProvider.notifier).select(i);
    final body = IndexedStack(index: index, children: _screens);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _railBreakpoint) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: onSelect,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ),
                  ],
                ),
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
            destinations: _destinations,
          ),
        );
      },
    );
  }
}
