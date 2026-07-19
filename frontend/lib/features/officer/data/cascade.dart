import 'officer_models.dart';

/// Computes which boundary-level pickers to show for the jurisdiction step,
/// given a department's [levels] and the chosen [designation].
///
/// Rules (per the enrollment spec):
///  - Cascade from the broadest level down to the level the designation
///    operates at — e.g. a WARD-level designation shows Region → Zone → Ward,
///    a ZONE-level designation shows only Region → Zone (don't force a Ward).
///  - The single top-most "CITY / city-wide" level is omitted from the cascade
///    (it's an implicit catch-all), UNLESS the designation itself operates at
///    that top level, in which case that one level is the only picker.
///
/// Returns the levels ordered broadest-first (highest rank first). The last
/// entry is always the designation's own level, so the final pick yields the
/// boundary to enroll against.
List<BoundaryLevel> cascadeLevelsFor(
  List<BoundaryLevel> levels,
  DesignationOption designation,
) {
  if (levels.isEmpty) return const [];

  final target = levels
      .where((l) => l.levelName == designation.levelName)
      .cast<BoundaryLevel?>()
      .firstWhere((l) => true, orElse: () => null);
  if (target == null) return const []; // designation level not in hierarchy

  final maxRank = levels.map((l) => l.levelRank).reduce((a, b) => a > b ? a : b);
  final targetRank = target.levelRank;

  // Levels from the designation's rank up to (but excluding) the top city rank.
  final cascade = levels
      .where((l) => l.levelRank >= targetRank && l.levelRank < maxRank)
      .toList()
    ..sort((a, b) => b.levelRank.compareTo(a.levelRank)); // broadest first

  // Designation operates at the very top (city) level: just that one picker.
  if (cascade.isEmpty) return [target];
  return cascade;
}
