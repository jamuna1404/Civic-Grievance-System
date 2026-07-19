import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:civicroute/core/utils/relative_time.dart';
import 'package:civicroute/features/citizen/complaints/data/complaint_models.dart';
import 'package:civicroute/features/citizen/complaints/data/track_repository.dart';
import 'package:civicroute/features/citizen/complaints/presentation/track_complaints_screen.dart';
import 'package:civicroute/features/citizen/complaints/presentation/widgets/status_timeline.dart';

ComplaintSummary _summary({
  String status = 'IN_PROGRESS',
  String dept = 'GCC_ELECT',
  List<String> images = const [],
}) {
  return ComplaintSummary(
    complaintId: 'c1',
    departmentId: dept,
    departmentName: 'GCC Electrical',
    descriptionText: 'Streetlight is out near the bus stop',
    inputMode: 'TEXT',
    status: status,
    imageUrls: images,
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
  );
}

void main() {
  group('relativeTime', () {
    final now = DateTime(2026, 7, 18, 12, 0, 0);
    test('formats recent and older times', () {
      expect(relativeTime(now.subtract(const Duration(seconds: 5)), now: now),
          'just now');
      expect(relativeTime(now.subtract(const Duration(minutes: 1)), now: now),
          '1 minute ago');
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now),
          '3 hours ago');
      expect(relativeTime(now.subtract(const Duration(days: 2)), now: now),
          '2 days ago');
      expect(relativeTime(now.subtract(const Duration(days: 10)), now: now),
          '1 week ago');
    });
  });

  group('ComplaintSummary.fromJson', () {
    test('parses fields and maps a known department to a short label', () {
      final s = ComplaintSummary.fromJson({
        'complaint_id': 'abc',
        'department_id': 'GCC_ELECT',
        'department_name': 'GCC Electrical',
        'description_text': 'Light out',
        'input_mode': 'VOICE',
        'status': 'SUBMITTED',
        'image_urls': ['u1', 'u2'],
        'created_at': '2026-07-10T10:00:00+00:00',
        'address_label': 'Anna Salai',
        'lat': 13.0827,
        'lon': 80.2707,
      });
      expect(s.department.label, 'Streetlights');
      expect(s.imageUrls, ['u1', 'u2']);
      expect(s.hasLocation, isTrue);
    });
  });

  Widget host(List<ComplaintSummary> items) => ProviderScope(
        overrides: [
          myComplaintsProvider.overrideWith((ref) async => items),
        ],
        child: const MaterialApp(home: TrackComplaintsScreen()),
      );

  testWidgets('list shows a card per complaint', (tester) async {
    await tester.pumpWidget(host([_summary(), _summary(status: 'RESOLVED')]));
    await tester.pumpAndSettle();

    expect(find.text('Streetlights'), findsNWidgets(2));
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
  });

  testWidgets('empty state shows friendly copy and a register button',
      (tester) async {
    await tester.pumpWidget(host([]));
    await tester.pumpAndSettle();

    expect(find.text('No complaints yet'), findsOneWidget);
    expect(find.text('Register a Complaint'), findsOneWidget);
  });

  group('StatusTimeline', () {
    Widget host(List<ComplaintHistoryEntry> history) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatusTimeline(history: history),
            ),
          ),
        );

    testWidgets('reached stages filled, unreached shown as pending',
        (tester) async {
      await tester.pumpWidget(host([
        ComplaintHistoryEntry(
          status: 'SUBMITTED',
          changedAt: DateTime(2026, 7, 10, 10),
        ),
        ComplaintHistoryEntry(
          status: 'IN_PROGRESS',
          changedAt: DateTime(2026, 7, 12, 9),
          remarks: 'Crew dispatched',
        ),
      ]));
      await tester.pumpAndSettle();

      // All four canonical stages are present…
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('Acknowledged'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
      // …with Acknowledged and Resolved not yet reached.
      expect(find.text('Pending'), findsNWidgets(2));
      expect(find.text('Crew dispatched'), findsOneWidget);
    });

    testWidgets('rejection node shows the reason inline and ends the timeline',
        (tester) async {
      await tester.pumpWidget(host([
        ComplaintHistoryEntry(
          status: 'SUBMITTED',
          changedAt: DateTime(2026, 7, 10, 10),
        ),
        ComplaintHistoryEntry(
          status: 'REJECTED',
          changedAt: DateTime(2026, 7, 11, 10),
          remarks: 'Duplicate of an existing complaint',
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Reason for rejection'), findsOneWidget);
      expect(find.text('Duplicate of an existing complaint'), findsOneWidget);
      // Forward stages beyond what was reached are not shown once rejected.
      expect(find.text('Resolved'), findsNothing);
      expect(find.text('In progress'), findsNothing);
    });
  });
}
