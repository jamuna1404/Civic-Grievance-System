import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:civicroute/core/network/api_client.dart';
import 'package:civicroute/features/citizen/complaints/application/complaint_draft_controller.dart';
import 'package:civicroute/features/citizen/complaints/application/location_service.dart';
import 'package:civicroute/features/citizen/complaints/data/complaint_repository.dart';
import 'package:civicroute/features/citizen/complaints/presentation/complaint_confirmation_screen.dart';
import 'package:civicroute/features/citizen/complaints/presentation/location_step_screen.dart';

class _FakeLocation implements LocationService {
  _FakeLocation({this.failure});
  final LocationFailure? failure;

  @override
  Future<LatLngPoint> getCurrentPosition() async {
    if (failure != null) throw failure!;
    return const LatLngPoint(13.0827, 80.2707);
  }

  @override
  Future<String?> reverseGeocode(LatLngPoint point) async => 'Anna Salai';
}

void main() {
  group('ComplaintDraft', () {
    test('location, department and voice flags flow into the draft', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(complaintDraftProvider.notifier);

      expect(container.read(complaintDraftProvider).inputMode, 'TEXT');
      n.markVoiceUsed();
      expect(container.read(complaintDraftProvider).inputMode, 'VOICE');

      expect(container.read(complaintDraftProvider).hasLocation, isFalse);
      n.setLocation(lat: 13.0, lon: 80.0, addressLabel: 'Chennai');
      expect(container.read(complaintDraftProvider).hasLocation, isTrue);

      n.setDepartment('GCC_ELECT');
      expect(container.read(complaintDraftProvider).departmentId, 'GCC_ELECT');

      n.clear();
      final cleared = container.read(complaintDraftProvider);
      expect(cleared.hasLocation, isFalse);
      expect(cleared.hasDepartment, isFalse);
      expect(cleared.inputMode, 'TEXT');
    });
  });

  group('ComplaintRepository.register', () {
    test('posts the full payload with bearer auth and parses the result',
        () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'complaint_id': 'abc123-def456',
            'status': 'SUBMITTED',
            'unassigned': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo =
          ComplaintRepository(ApiClient(client: mock, baseUrl: 'http://test'));

      final result = await repo.register(
        token: 'tok-123',
        departmentId: 'GCC_ELECT',
        descriptionText: 'Streetlight out',
        inputMode: 'VOICE',
        imageUrls: const ['https://x/a.jpg'],
        lat: 13.0827,
        lon: 80.2707,
        addressLabel: 'Anna Salai',
      );

      expect(result.complaintId, 'abc123-def456');
      expect(result.status, 'SUBMITTED');
      expect(result.unassigned, isFalse);

      expect(captured.method, 'POST');
      expect(captured.url.path, '/complaints/register');
      expect(captured.headers['Authorization'], 'Bearer tok-123');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['department_id'], 'GCC_ELECT');
      expect(body['description_text'], 'Streetlight out');
      expect(body['input_mode'], 'VOICE');
      expect(body['image_urls'], ['https://x/a.jpg']);
      expect(body['lat'], 13.0827);
      expect(body['lon'], 80.2707);
      expect(body['address_label'], 'Anna Salai');
    });

    test('surfaces the backend error message', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Unknown department.'}),
          400,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo =
          ComplaintRepository(ApiClient(client: mock, baseUrl: 'http://test'));

      expect(
        () => repo.register(
          token: 't',
          departmentId: 'NOPE',
          descriptionText: 'x',
          inputMode: 'TEXT',
          imageUrls: const [],
          lat: 1,
          lon: 1,
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Unknown department.')),
      );
    });
  });

  testWidgets('location step: permanently-denied permission shows a dialog',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(
            _FakeLocation(
              failure: LocationFailure('denied', permanentlyDenied: true),
            ),
          ),
        ],
        child: const MaterialApp(home: LocationStepScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 3'), findsOneWidget);
    await tester.tap(find.text('Use My Current Location'));
    await tester.pumpAndSettle();

    expect(find.text('Location access needed'), findsOneWidget);
  });

  testWidgets('confirmation screen shows the complaint id and track shortcut',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ComplaintConfirmationScreen(
          args: ComplaintConfirmationArgs(complaintId: 'abcd1234-5678-90'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complaint Registered'), findsOneWidget);
    expect(find.text('#ABCD1234'), findsOneWidget);
    expect(find.text('Track this complaint'), findsOneWidget);
  });
}
