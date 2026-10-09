import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../application/officer_realtime_controller.dart';
import '../application/officer_session_controller.dart';
import 'allotted_complaints_screen.dart';
import 'officer_complaint_detail_screen.dart';
import 'officer_profile_screen.dart';
import 'officer_track_screen.dart';
import 'team_complaints_screen.dart';

/// Selected officer-shell tab (0=Allotted, 1=Track, 2=[Manage Team], last=Profile).
final officerTabProvider = NotifierProvider<_OfficerTabNotifier, int>(
  _OfficerTabNotifier.new,
);

class _OfficerTabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void select(int index) => state = index;
}

/// Officer main navigation shell — same responsive pattern as the citizen app
/// (bottom bar on phones, side rail on wide layouts). A 4th "Manage Team" tab
/// only appears for officers who actually have subordinates — determined at
/// login (OfficerSession.managesTeam) — never shown empty for first-responder
/// designations like Junior Engineer / Sub-Inspector.
class OfficerShell extends ConsumerWidget {
  const OfficerShell({super.key});

  static const _railBreakpoint = 720.0;

  static const _baseScreens = [
    AllottedComplaintsScreen(),
    OfficerTrackScreen(),
  ];

  static const _baseDestinations = [
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
  ];

  static const _teamScreen = TeamComplaintsScreen();

  static const _teamDestination = NavigationDestination(
    icon: Icon(Icons.groups_outlined),
    selectedIcon: Icon(Icons.groups),
    label: 'Manage Team',
  );

  static const _profileScreen = OfficerProfileScreen();

  static const _profileDestination = NavigationDestination(
    icon: Icon(Icons.person_outline),
    selectedIcon: Icon(Icons.person),
    label: 'Profile',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(officerTabProvider);
    final managesTeam =
        ref.watch(officerSessionProvider)?.managesTeam ?? false;

    // Activate the realtime closure-request subscription (no-op for officers
    // without a team) and surface each alert as a tap-to-review banner.
    ref.listen<ClosureRequestAlert?>(officerRealtimeProvider, (_, alert) {
      if (alert == null) return;
      final officerName = alert.complaint.officerName ?? 'an officer';
      // clearSnackBars() (not just hideCurrentSnackBar) drops any queued
      // banner too, so rapid-fire closure requests replace cleanly and never
      // stack up on screen.
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('New closure request from $officerName — tap to review'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Review',
              onPressed: () => context.push(
                AppRoutes.officerComplaintDetail,
                extra: OfficerComplaintArgs(
                  complaint: alert.complaint,
                  canUpdateStatus: false,
                  canReview: true,
                ),
              ),
            ),
          ),
        );
      ref.read(officerRealtimeProvider.notifier).consume();
    });

    final screens = [
      ..._baseScreens,
      if (managesTeam) _teamScreen,
      _profileScreen,
    ];
    final destinations = [
      ..._baseDestinations,
      if (managesTeam) _teamDestination,
      _profileDestination,
    ];

    void onSelect(int i) => ref.read(officerTabProvider.notifier).select(i);
    final clampedIndex = index < screens.length ? index : 0;
    final body = IndexedStack(index: clampedIndex, children: screens);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _railBreakpoint) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: clampedIndex,
                  onDestinationSelected: onSelect,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in destinations)
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
            selectedIndex: clampedIndex,
            onDestinationSelected: onSelect,
            destinations: destinations,
          ),
        );
      },
    );
  }
}
