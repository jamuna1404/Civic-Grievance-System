import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:civicroute/core/network/api_client.dart';
import 'package:civicroute/features/officer/data/officer_models.dart';
import 'package:civicroute/features/officer/data/officer_repository.dart';
import 'package:civicroute/features/officer/presentation/enroll/jurisdiction_cascade.dart';

/// Fake repo returning canned boundaries per level, simulating a department
/// whose declared REGION level has no rows (GCC_ELECT-style gap).
class _FakeOfficerRepo extends OfficerRepository {
  _FakeOfficerRepo() : super(ApiClient(baseUrl: 'http://test'));

  final _byLevel = {
    'REGION': <BoundaryOption>[], // declared but empty — should be skipped
    'ZONE': const [
      BoundaryOption(boundaryId: 20, boundaryName: 'Adyar', levelName: 'ZONE'),
    ],
    'WARD': const [
      BoundaryOption(
          boundaryId: 30,
          boundaryName: 'Ward 175',
          levelName: 'WARD',
          parentBoundaryId: 20),
    ],
  };

  @override
  Future<List<BoundaryOption>> boundaries(
    String departmentId, {
    required String levelName,
    int? parentId,
  }) async =>
      _byLevel[levelName] ?? [];
}

const _levels = [
  BoundaryLevel(levelRank: 1, levelName: 'WARD', displayLabel: 'Ward'),
  BoundaryLevel(levelRank: 2, levelName: 'ZONE', displayLabel: 'Zone'),
  BoundaryLevel(levelRank: 3, levelName: 'REGION', displayLabel: 'Region'),
  BoundaryLevel(levelRank: 4, levelName: 'CITY', displayLabel: 'City-wide'),
];

void main() {
  testWidgets('cascade skips a declared level that has no boundary data',
      (tester) async {
    int? selectedBoundary;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          officerRepositoryProvider.overrideWithValue(_FakeOfficerRepo()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: JurisdictionCascade(
              departmentId: 'GCC_ELECT',
              designation: const DesignationOption(
                designationId: 1,
                designationName: 'Junior Engineer',
                levelName: 'WARD',
                rankOrder: 1,
              ),
              levels: _levels,
              onSelected: (id, _) => selectedBoundary = id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Region (empty) is skipped; the first picker is Zone.
    expect(find.text('Zone'), findsOneWidget);
    expect(find.text('Region'), findsNothing);

    // Choose the zone → ward options load.
    await tester.tap(find.byType(DropdownButtonFormField<BoundaryOption>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adyar').last);
    await tester.pumpAndSettle();

    expect(find.text('Ward'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<BoundaryOption>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ward 175').last);
    await tester.pumpAndSettle();

    expect(selectedBoundary, 30);
  });
}
