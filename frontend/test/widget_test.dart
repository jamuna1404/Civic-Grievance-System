// Basic smoke test for the CivicRoute scaffolding.
//
// Verifies the app boots and the theme showcase screen renders. Real feature
// tests arrive alongside their features in later prompts.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:civicroute/core/theme/theme_mode_provider.dart';
import 'package:civicroute/main.dart';

void main() {
  testWidgets('Logged-out app boots to the role select screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const CivicRouteApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('I’m a Citizen'), findsOneWidget);
    expect(find.text('I’m an Officer'), findsOneWidget);
  });
}
