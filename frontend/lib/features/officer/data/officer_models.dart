/// A designation within a department (e.g. "Junior Engineer" at WARD level).
class DesignationOption {
  const DesignationOption({
    required this.designationId,
    required this.designationName,
    required this.levelName,
    required this.rankOrder,
  });

  final int designationId;
  final String designationName;

  /// The boundary level this designation operates at (e.g. 'WARD', 'ZONE').
  final String levelName;
  final int rankOrder;

  factory DesignationOption.fromJson(Map<String, dynamic> json) =>
      DesignationOption(
        designationId: json['designation_id'] as int,
        designationName: json['designation_name'] as String,
        levelName: json['level_name'] as String,
        rankOrder: json['rank_order'] as int,
      );
}

/// One level in a department's boundary hierarchy.
class BoundaryLevel {
  const BoundaryLevel({
    required this.levelRank,
    required this.levelName,
    required this.displayLabel,
  });

  /// 1 = most granular (e.g. Ward / Section); increases outward.
  final int levelRank;
  final String levelName;
  final String displayLabel;

  factory BoundaryLevel.fromJson(Map<String, dynamic> json) => BoundaryLevel(
        levelRank: json['level_rank'] as int,
        levelName: json['level_name'] as String,
        displayLabel: json['display_label'] as String,
      );
}

/// A concrete boundary area (e.g. "Adyar" zone, "Ward 175").
class BoundaryOption {
  const BoundaryOption({
    required this.boundaryId,
    required this.boundaryName,
    required this.levelName,
    this.parentBoundaryId,
  });

  final int boundaryId;
  final String boundaryName;
  final String levelName;
  final int? parentBoundaryId;

  factory BoundaryOption.fromJson(Map<String, dynamic> json) => BoundaryOption(
        boundaryId: json['boundary_id'] as int,
        boundaryName: json['boundary_name'] as String,
        levelName: json['level_name'] as String,
        parentBoundaryId: json['parent_boundary_id'] as int?,
      );
}
