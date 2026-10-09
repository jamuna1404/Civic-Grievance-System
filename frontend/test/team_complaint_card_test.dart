import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:civicroute/features/citizen/complaints/data/complaint_models.dart';
import 'package:civicroute/features/officer/presentation/widgets/team_complaint_card.dart';

ComplaintSummary _complaint(String status) => ComplaintSummary(
      complaintId: 'c-1',
      departmentId: 'GCC_ENG_ROADS',
      departmentName: 'GCC Roads',
      descriptionText: 'Pothole on Main St',
      inputMode: 'TEXT',
      status: status,
      imageUrls: const [],
      createdAt: DateTime(2026, 7, 10, 10),
      officerName: 'R. Kumar',
      officerDesignationName: 'Junior Engineer',
    );

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('Action Needed badge shows only for RESOLUTION_REQUESTED',
      (tester) async {
    await tester.pumpWidget(_host(
      TeamComplaintCard(
        complaint: _complaint('RESOLUTION_REQUESTED'),
        onTap: () {},
      ),
    ));
    expect(find.text('ACTION NEEDED'), findsOneWidget);
    // Subordinate officer identity is fine to show (it's an officer).
    expect(find.textContaining('R. Kumar'), findsOneWidget);

    await tester.pumpWidget(_host(
      TeamComplaintCard(complaint: _complaint('IN_PROGRESS'), onTap: () {}),
    ));
    expect(find.text('ACTION NEEDED'), findsNothing);
  });

  testWidgets('highlighted card renders cleanly in dark mode', (tester) async {
    await tester.pumpWidget(_host(
      TeamComplaintCard(
        complaint: _complaint('RESOLUTION_REQUESTED'),
        onTap: () {},
      ),
      brightness: Brightness.dark,
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('ACTION NEEDED'), findsOneWidget);
  });

  testWidgets('card is tappable', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(
      TeamComplaintCard(
        complaint: _complaint('RESOLUTION_REQUESTED'),
        onTap: () => tapped = true,
      ),
    ));
    await tester.tap(find.byType(TeamComplaintCard));
    expect(tapped, isTrue);
  });
}
