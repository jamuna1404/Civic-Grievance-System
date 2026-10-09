import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../citizen/auth/data/auth_repository.dart' show apiClientProvider;
import 'officer_models.dart';

/// Result of verifying an officer login OTP.
class OfficerVerifyResult {
  const OfficerVerifyResult({
    required this.newUser,
    this.sessionToken,
    this.fullName,
    this.status,
    this.officerId,
    this.managesTeam = false,
  });

  /// True when no officer exists for the number yet — they must enroll.
  final bool newUser;
  final String? sessionToken;
  final String? fullName;
  final String? status;
  final String? officerId;
  final bool managesTeam;
}

/// Result of a successful enrollment.
class OfficerEnrollment {
  const OfficerEnrollment({
    required this.officerId,
    required this.fullName,
    required this.status,
    required this.sessionToken,
  });

  final String officerId;
  final String fullName;
  final String status;
  final String sessionToken;
}

class OfficerRepository {
  OfficerRepository(this._api);

  final ApiClient _api;

  // --- Auth (login) ---------------------------------------------------------

  Future<String> sendOtp(String phoneNumber) async {
    final json = await _api.postJson(
      '/auth/officer/send-otp',
      {'phone_number': phoneNumber},
    );
    return json['phone_number'] as String;
  }

  Future<OfficerVerifyResult> verifyOtp(
    String phoneNumber,
    String otpCode,
  ) async {
    final json = await _api.postJson(
      '/auth/officer/verify-otp',
      {'phone_number': phoneNumber, 'otp_code': otpCode},
    );
    return OfficerVerifyResult(
      newUser: json['new_user'] as bool,
      sessionToken: json['session_token'] as String?,
      fullName: json['full_name'] as String?,
      status: json['status'] as String?,
      officerId: json['officer_id'] as String?,
      managesTeam: json['manages_team'] as bool? ?? false,
    );
  }

  // --- Reference data (enrollment pickers) ----------------------------------

  Future<List<DesignationOption>> designations(String departmentId) async {
    final data =
        await _api.getJsonList('/departments/$departmentId/designations');
    return data
        .map((e) => DesignationOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<BoundaryLevel>> boundaryLevels(String departmentId) async {
    final data =
        await _api.getJsonList('/departments/$departmentId/boundary-levels');
    return data
        .map((e) => BoundaryLevel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<BoundaryOption>> boundaries(
    String departmentId, {
    required String levelName,
    int? parentId,
  }) async {
    final query = StringBuffer('level_name=$levelName');
    if (parentId != null) query.write('&parent_id=$parentId');
    final data = await _api.getJsonList(
      '/departments/$departmentId/boundaries?$query',
    );
    return data
        .map((e) => BoundaryOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- Enrollment -----------------------------------------------------------

  /// Enrolls a first-time officer. Throws [ApiException] with statusCode 409
  /// when the (department, designation, area) seat is already filled.
  Future<OfficerEnrollment> enroll({
    required String fullName,
    required String phoneNumber,
    required String departmentId,
    required int designationId,
    required int boundaryId,
    String? employeeId,
    String? email,
  }) async {
    final json = await _api.postJson('/officer/enroll', {
      'full_name': fullName,
      'phone_number': phoneNumber,
      'department_id': departmentId,
      'designation_id': designationId,
      'boundary_id': boundaryId,
      'employee_id': employeeId,
      'email': email,
    });
    return OfficerEnrollment(
      officerId: json['officer_id'] as String,
      fullName: json['full_name'] as String,
      status: json['status'] as String,
      sessionToken: json['session_token'] as String,
    );
  }
}

final officerRepositoryProvider = Provider<OfficerRepository>(
  (ref) => OfficerRepository(ref.watch(apiClientProvider)),
);

/// Designations for a department (lowest rank first).
final officerDesignationsProvider = FutureProvider.autoDispose
    .family<List<DesignationOption>, String>(
  (ref, departmentId) =>
      ref.read(officerRepositoryProvider).designations(departmentId),
);

/// Boundary levels (hierarchy) for a department.
final officerBoundaryLevelsProvider = FutureProvider.autoDispose
    .family<List<BoundaryLevel>, String>(
  (ref, departmentId) =>
      ref.read(officerRepositoryProvider).boundaryLevels(departmentId),
);
