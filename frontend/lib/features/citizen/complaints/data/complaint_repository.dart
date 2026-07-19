import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;

/// Outcome of registering a complaint.
class RegisteredComplaint {
  const RegisteredComplaint({
    required this.complaintId,
    required this.status,
    this.unassigned = false,
  });

  final String complaintId;
  final String status;

  /// True when no officer could be routed for the location (still recorded).
  final bool unassigned;
}

class ComplaintRepository {
  ComplaintRepository(this._api);

  final ApiClient _api;

  Future<RegisteredComplaint> register({
    required String token,
    required String departmentId,
    required String descriptionText,
    required String inputMode,
    required List<String> imageUrls,
    required double lat,
    required double lon,
    String? addressLabel,
  }) async {
    final json = await _api.postJson(
      '/complaints/register',
      {
        'department_id': departmentId,
        'description_text': descriptionText,
        'input_mode': inputMode,
        'image_urls': imageUrls,
        'lat': lat,
        'lon': lon,
        'address_label': addressLabel,
      },
      token: token,
    );
    return RegisteredComplaint(
      complaintId: json['complaint_id'] as String,
      status: json['status'] as String,
      unassigned: (json['unassigned'] as bool?) ?? false,
    );
  }
}

final complaintRepositoryProvider = Provider<ComplaintRepository>(
  (ref) => ComplaintRepository(ref.watch(apiClientProvider)),
);
