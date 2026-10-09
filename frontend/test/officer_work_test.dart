import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:civicroute/core/network/api_client.dart';
import 'package:civicroute/core/widgets/app_buttons.dart';
import 'package:civicroute/features/citizen/complaints/data/complaint_status.dart';
import 'package:civicroute/features/officer/data/officer_work_repository.dart';
import 'package:civicroute/features/officer/presentation/officer_complaint_detail_screen.dart';
import 'package:civicroute/features/officer/presentation/widgets/status_update_control.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // Point 1: exactly one forward action per status, none for terminal/awaiting.
  group('StatusUpdateControl one-action invariant', () {
    testWidgets('every status shows at most one action button', (tester) async {
      const expected = {
        ComplaintStatus.submitted: 'Acknowledge',
        ComplaintStatus.acknowledged: 'Start Work',
        ComplaintStatus.inProgress: 'Request Closure',
        ComplaintStatus.resolutionRequested: null,
        ComplaintStatus.resolved: null,
        ComplaintStatus.rejected: null,
      };
      for (final entry in expected.entries) {
        await tester.pumpWidget(_host(StatusUpdateControl(
          current: entry.key,
          submitting: false,
          onSubmit: (_, __) {},
        )));
        if (entry.value == null) {
          expect(find.byType(PrimaryButton), findsNothing,
              reason: '${entry.key} must show no action button');
        } else {
          expect(find.byType(PrimaryButton), findsOneWidget,
              reason: '${entry.key} must show exactly one action button');
          expect(find.text(entry.value!), findsOneWidget);
        }
      }
    });
  });

  // Points 1 & 3: control gating across Allotted vs Manage Team contexts.
  group('officerDetailActionFor', () {
    test('Manage Team (review) only for RESOLUTION_REQUESTED', () {
      for (final s in ComplaintStatus.values) {
        final action = officerDetailActionFor(
          canReview: true, canUpdateStatus: false, status: s,
        );
        expect(
          action,
          s == ComplaintStatus.resolutionRequested
              ? OfficerDetailAction.review
              : OfficerDetailAction.none,
          reason: 'Manage Team context, status $s',
        );
      }
    });

    test('RESOLVED and REJECTED never yield review buttons in any context', () {
      for (final terminal in [
        ComplaintStatus.resolved,
        ComplaintStatus.rejected,
      ]) {
        // Manage Team: read-only.
        expect(
          officerDetailActionFor(
              canReview: true, canUpdateStatus: false, status: terminal),
          OfficerDetailAction.none,
        );
        // Allotted: status-update control (which itself renders a no-button
        // banner for terminal states).
        expect(
          officerDetailActionFor(
              canReview: false, canUpdateStatus: true, status: terminal),
          OfficerDetailAction.statusUpdate,
        );
      }
    });

    test('Track (read-only) shows nothing regardless of status', () {
      for (final s in ComplaintStatus.values) {
        expect(
          officerDetailActionFor(
              canReview: false, canUpdateStatus: false, status: s),
          OfficerDetailAction.none,
        );
      }
    });
  });

  group('StatusUpdateControl', () {
    testWidgets('shows the correct forward action per status', (tester) async {
      await tester.pumpWidget(_host(StatusUpdateControl(
        current: ComplaintStatus.submitted,
        submitting: false,
        onSubmit: (_, __) {},
      )));
      expect(find.text('Acknowledge'), findsOneWidget);

      await tester.pumpWidget(_host(StatusUpdateControl(
        current: ComplaintStatus.acknowledged,
        submitting: false,
        onSubmit: (_, __) {},
      )));
      expect(find.text('Start Work'), findsOneWidget);

      await tester.pumpWidget(_host(StatusUpdateControl(
        current: ComplaintStatus.inProgress,
        submitting: false,
        onSubmit: (_, __) {},
      )));
      expect(find.text('Request Closure'), findsOneWidget);
    });

    testWidgets('awaiting review shows a banner, not a button', (tester) async {
      await tester.pumpWidget(_host(StatusUpdateControl(
        current: ComplaintStatus.resolutionRequested,
        submitting: false,
        onSubmit: (_, __) {},
      )));
      expect(find.textContaining('awaiting supervisor approval'), findsOneWidget);
      expect(find.text('Request Closure'), findsNothing);
    });

    testWidgets('terminal status shows no action', (tester) async {
      await tester.pumpWidget(_host(StatusUpdateControl(
        current: ComplaintStatus.resolved,
        submitting: false,
        onSubmit: (_, __) {},
      )));
      expect(find.textContaining('No further action'), findsOneWidget);
      expect(find.text('Request Closure'), findsNothing);
    });

    testWidgets('acknowledge submits immediately with no remarks dialog',
        (tester) async {
      String? gotStatus;
      String? gotRemarks;
      await tester.pumpWidget(_host(StatusUpdateControl(
        current: ComplaintStatus.submitted,
        submitting: false,
        onSubmit: (s, r) {
          gotStatus = s;
          gotRemarks = r;
        },
      )));

      await tester.tap(find.text('Acknowledge'));
      await tester.pump();

      expect(gotStatus, 'ACKNOWLEDGED');
      expect(gotRemarks, '');
    });

    testWidgets('request closure opens a remarks dialog before submitting',
        (tester) async {
      String? gotStatus;
      String? gotRemarks;
      await tester.pumpWidget(_host(StatusUpdateControl(
        current: ComplaintStatus.inProgress,
        submitting: false,
        onSubmit: (s, r) {
          gotStatus = s;
          gotRemarks = r;
        },
      )));

      await tester.tap(find.text('Request Closure'));
      await tester.pumpAndSettle();

      // Cancelling submits nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gotStatus, isNull);

      await tester.tap(find.text('Request Closure'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Fixed the light');
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();

      expect(gotStatus, 'RESOLUTION_REQUESTED');
      expect(gotRemarks, 'Fixed the light');
    });
  });

  group('OfficerWorkRepository.updateStatus', () {
    test('PUTs status + remarks with bearer auth', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({'complaint_id': 'c1', 'status': 'RESOLVED'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo =
          OfficerWorkRepository(ApiClient(client: mock, baseUrl: 'http://t'));

      await repo.updateStatus(
        token: 'tok',
        complaintId: 'c1',
        newStatus: 'RESOLVED',
        remarks: 'done',
      );

      expect(captured.method, 'PUT');
      expect(captured.url.path, '/complaints/c1/status');
      expect(captured.headers['Authorization'], 'Bearer tok');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['new_status'], 'RESOLVED');
      expect(body['remarks'], 'done');
    });
  });
}
