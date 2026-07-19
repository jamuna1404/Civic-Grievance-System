import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:civicroute/core/network/api_client.dart';
import 'package:civicroute/features/officer/data/cascade.dart';
import 'package:civicroute/features/officer/data/officer_models.dart';
import 'package:civicroute/features/officer/data/officer_repository.dart';

// GCC-style hierarchy: Ward(1) → Zone(2) → Region(3) → City(4).
const _gccLevels = [
  BoundaryLevel(levelRank: 1, levelName: 'WARD', displayLabel: 'Ward'),
  BoundaryLevel(levelRank: 2, levelName: 'ZONE', displayLabel: 'Zone'),
  BoundaryLevel(levelRank: 3, levelName: 'REGION', displayLabel: 'Region'),
  BoundaryLevel(levelRank: 4, levelName: 'CITY', displayLabel: 'City-wide'),
];

DesignationOption _desig(String level, {int rank = 1}) => DesignationOption(
      designationId: rank,
      designationName: 'Role',
      levelName: level,
      rankOrder: rank,
    );

void main() {
  group('cascadeLevelsFor', () {
    test('ward-level designation cascades Region → Zone → Ward', () {
      final levels = cascadeLevelsFor(_gccLevels, _desig('WARD'));
      expect(levels.map((l) => l.levelName), ['REGION', 'ZONE', 'WARD']);
    });

    test('zone-level designation stops at Zone (no Ward pick)', () {
      final levels = cascadeLevelsFor(_gccLevels, _desig('ZONE'));
      expect(levels.map((l) => l.levelName), ['REGION', 'ZONE']);
    });

    test('excludes the top city-wide level for sub-city designations', () {
      final levels = cascadeLevelsFor(_gccLevels, _desig('REGION'));
      expect(levels.map((l) => l.levelName), ['REGION']);
      expect(levels.any((l) => l.levelName == 'CITY'), isFalse);
    });

    test('city-level designation shows only the city level', () {
      final levels = cascadeLevelsFor(_gccLevels, _desig('CITY'));
      expect(levels.map((l) => l.levelName), ['CITY']);
    });

    test('returns empty when the designation level is not in the hierarchy', () {
      expect(cascadeLevelsFor(_gccLevels, _desig('NOPE')), isEmpty);
    });

    test('TANGEDCO-style deep hierarchy cascades correctly', () {
      const levels = [
        BoundaryLevel(levelRank: 1, levelName: 'SECTION', displayLabel: 'Section'),
        BoundaryLevel(levelRank: 2, levelName: 'SUBDIVISION', displayLabel: 'Sub'),
        BoundaryLevel(levelRank: 3, levelName: 'DIVISION', displayLabel: 'Div'),
        BoundaryLevel(levelRank: 4, levelName: 'CIRCLE', displayLabel: 'Circle'),
        BoundaryLevel(levelRank: 5, levelName: 'CITY', displayLabel: 'City'),
      ];
      final result = cascadeLevelsFor(levels, _desig('SECTION'));
      expect(result.map((l) => l.levelName),
          ['CIRCLE', 'DIVISION', 'SUBDIVISION', 'SECTION']);
    });
  });

  group('OfficerRepository.enroll', () {
    test('posts the full payload and parses the officer', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'officer_id': 'off-1',
            'full_name': 'R. Kumar',
            'status': 'PENDING_VERIFICATION',
            'session_token': 'tok',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo =
          OfficerRepository(ApiClient(client: mock, baseUrl: 'http://test'));

      final result = await repo.enroll(
        fullName: 'R. Kumar',
        phoneNumber: '9876543210',
        departmentId: 'GCC_ENG_ROADS',
        designationId: 1,
        boundaryId: 11,
        employeeId: 'EMP-42',
        email: 'k@x.in',
      );

      expect(result.status, 'PENDING_VERIFICATION');
      expect(result.sessionToken, 'tok');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['department_id'], 'GCC_ENG_ROADS');
      expect(body['designation_id'], 1);
      expect(body['boundary_id'], 11);
      expect(body['employee_id'], 'EMP-42');
    });

    test('surfaces a 409 position-taken conflict as an ApiException', () async {
      const detail =
          'This position is already filled for the selected area. '
          'Please contact your department administrator.';
      final mock = MockClient((req) async => http.Response(
            jsonEncode({'detail': detail}),
            409,
            headers: {'content-type': 'application/json'},
          ));
      final repo =
          OfficerRepository(ApiClient(client: mock, baseUrl: 'http://test'));

      await expectLater(
        repo.enroll(
          fullName: 'X',
          phoneNumber: '9876543210',
          departmentId: 'GCC_ENG_ROADS',
          designationId: 1,
          boundaryId: 11,
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', detail)),
      );
    });
  });
}
