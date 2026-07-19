import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:civicroute/core/theme/theme_mode_provider.dart';
import 'package:civicroute/features/citizen/complaints/data/track_repository.dart';
import 'package:civicroute/main.dart';

/// Boots the app with a persisted citizen session so it lands on the shell.
Future<void> _pumpLoggedIn(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'citizen_session_token': 'fake-token',
    'citizen_full_name': 'Priya Raman',
    'citizen_phone_number': '+919876543210',
    'citizen_id': 'cid-123',
  });
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Avoid a real network fetch (and infinite loading spinner) from the
        // Track tab, which is built eagerly in the shell's IndexedStack.
        myComplaintsProvider.overrideWith((ref) async => []),
      ],
      child: const CivicRouteApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('narrow layout shows a bottom bar with 3 destinations',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLoggedIn(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Track'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('wide layout shows a side rail instead of a bottom bar',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLoggedIn(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('profile tab shows name field and read-only phone',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLoggedIn(tester);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Profile & Settings'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Priya Raman'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });
}
