import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:civicroute/core/theme/theme_mode_provider.dart';
import 'package:civicroute/features/officer/data/officer_work_repository.dart';
import 'package:civicroute/main.dart';

/// Boots the app with a persisted officer session so it lands on the officer
/// shell, with the work providers stubbed so no network fetch runs.
Future<void> _pumpOfficer(
  WidgetTester tester, {
  required bool managesTeam,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({
    'officer_session_token': 'tok',
    'officer_full_name': 'S. Devi',
    'officer_id': 'off-1',
    'officer_status': 'ACTIVE',
    'officer_manages_team': managesTeam,
  });
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        allottedComplaintsProvider.overrideWith((ref) async => []),
        officerTrackProvider.overrideWith((ref) async => []),
        teamComplaintsProvider.overrideWith((ref) async => []),
      ],
      child: const CivicRouteApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Manage Team tab is hidden for a first-responder officer',
      (tester) async {
    await _pumpOfficer(tester, managesTeam: false);

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.length, 3); // Allotted, Track, Profile
    expect(find.text('Manage Team'), findsNothing);
  });

  testWidgets('Manage Team tab is shown for a higher-rank officer',
      (tester) async {
    await _pumpOfficer(tester, managesTeam: true);

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.length, 4); // + Manage Team
    expect(find.text('Manage Team'), findsWidgets);
  });
}
