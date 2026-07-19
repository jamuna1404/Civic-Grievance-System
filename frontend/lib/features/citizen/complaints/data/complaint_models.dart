import 'department_catalog.dart';

/// A complaint as returned by the list endpoint (rich enough to also render the
/// detail header, gallery, description, and map without a second fetch).
class ComplaintSummary {
  const ComplaintSummary({
    required this.complaintId,
    required this.departmentId,
    required this.departmentName,
    required this.descriptionText,
    required this.inputMode,
    required this.status,
    required this.imageUrls,
    required this.createdAt,
    this.addressLabel,
    this.lat,
    this.lon,
    this.citizenName,
    this.citizenPhone,
  });

  final String complaintId;
  final String departmentId;
  final String departmentName;
  final String descriptionText;
  final String inputMode;
  final String status;
  final List<String> imageUrls;
  final DateTime createdAt;
  final String? addressLabel;
  final double? lat;
  final double? lon;

  /// Citizen contact — populated for officer-facing views (for follow-up).
  final String? citizenName;
  final String? citizenPhone;

  bool get hasLocation => lat != null && lon != null;

  /// Client-side department option (short label + icon) for this complaint.
  DepartmentOption get department => kDepartments.firstWhere(
        (d) => d.id == departmentId,
        orElse: () => DepartmentOption(
          id: departmentId,
          label: departmentName,
          icon: kFallbackDepartmentIcon,
        ),
      );

  factory ComplaintSummary.fromJson(Map<String, dynamic> json) {
    return ComplaintSummary(
      complaintId: json['complaint_id'] as String,
      departmentId: json['department_id'] as String,
      departmentName: json['department_name'] as String,
      descriptionText: json['description_text'] as String,
      inputMode: (json['input_mode'] as String?) ?? 'TEXT',
      status: json['status'] as String,
      imageUrls:
          (json['image_urls'] as List?)?.whereType<String>().toList() ?? [],
      createdAt: DateTime.parse(json['created_at'] as String),
      addressLabel: json['address_label'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
      citizenName: json['citizen_name'] as String?,
      citizenPhone: json['citizen_phone'] as String?,
    );
  }
}

/// One entry in a complaint's status history.
class ComplaintHistoryEntry {
  const ComplaintHistoryEntry({
    required this.status,
    required this.changedAt,
    this.remarks,
    this.officerName,
  });

  final String status;
  final DateTime changedAt;
  final String? remarks;
  final String? officerName;

  factory ComplaintHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ComplaintHistoryEntry(
      status: json['status'] as String,
      changedAt: DateTime.parse(json['changed_at'] as String),
      remarks: json['remarks'] as String?,
      officerName: json['officer_name'] as String?,
    );
  }
}
