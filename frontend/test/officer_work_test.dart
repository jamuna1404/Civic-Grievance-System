import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:civicroute/core/network/api_client.dart';
import 'package:civicroute/features/citizen/complaints/data/complaint_status.dart';
import 'package:civicroute/features/officer/data/officer_work_repository.dart';
import 'package:civicroute/features/officer/presentation/widgets/status_update_control.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
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
      expect(find.text('Start Progress'), findsOneWidget);

      await tester.pumpWidget(_host(StatusUpdateControl(
        current: ComplaintStatus.inProgress,
        submitting: false,
        onSubmit: (_, __) {},
      )));
      expect(find.text('Mark Resolved'), findsOneWidget);
    });

    testWidgets('terminal status shows no action', (tester) async {
      await tester.pumpWidget(_host(StatusUpdateControl(
        current: ComplaintStatus.resolved,
        submitting: false,
        onSubmit: (_, __) {},
      )));
      expect(find.textContaining('No further action'), findsOneWidget);
      expect(find.text('Mark Resolved'), findsNothing);
    });

    testWidgets('submits the target status with typed remarks', (tester) async {
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

      await tester.enterText(find.byType(TextField), 'Fixed the light');
      await tester.tap(find.text('Mark Resolved'));
      await tester.pump();

      expect(gotStatus, 'RESOLVED');
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
