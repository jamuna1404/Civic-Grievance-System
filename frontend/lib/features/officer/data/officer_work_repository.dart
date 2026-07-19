import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../citizen/auth/data/auth_repository.dart' show apiClientProvider;
import '../../citizen/complaints/data/complaint_models.dart';
import '../../citizen/complaints/data/track_repository.dart'
    show trackRepositoryProvider;
import '../../citizen/profile/data/citizen_repository.dart' show ThemeModeApi;
import '../application/officer_session_controller.dart';

/// The officer's read-only profile.
class OfficerProfile {
  const OfficerProfile({
    required this.fullName,
    required this.phone,
    required this.departmentName,
    required this.designationName,
    required this.jurisdictionName,
    required this.status,
    required this.themeMode,
    this.email,
    this.employeeId,
  });

  final String fullName;
  final String phone;
  final String departmentName;
  final String designationName;
  final String jurisdictionName;
  final String status;
  final ThemeMode themeMode;
  final String? email;
  final String? employeeId;

  factory OfficerProfile.fromJson(Map<String, dynamic> json) => OfficerProfile(
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        departmentName: json['department_name'] as String,
        designationName: json['designation_name'] as String,
        jurisdictionName: json['jurisdiction_name'] as String,
        status: json['status'] as String,
        themeMode: ThemeModeApi.fromApi(json['theme_mode'] as String?),
        email: json['email'] as String?,
        employeeId: json['employee_id'] as String?,
      );
}

class OfficerWorkRepository {
  OfficerWorkRepository(this._api);

  final ApiClient _api;

  Future<List<ComplaintSummary>> allotted({
    required String token,
    required String officerId,
    String status = 'active',
  }) async {
    final data = await _api.getJsonList(
      '/officer/$officerId/complaints?status=$status',
      token: token,
    );
    return data
        .map((e) => ComplaintSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ComplaintSummary>> jurisdiction({
    required String token,
    required String officerId,
  }) async {
    final data =
        await _api.getJsonList('/officer/$officerId/track', token: token);
    return data
        .map((e) => ComplaintSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateStatus({
    required String token,
    required String complaintId,
    required String newStatus,
    String? remarks,
  }) async {
    await _api.putJson(
      '/complaints/$complaintId/status',
      {'new_status': newStatus, if (remarks != null) 'remarks': remarks},
      token: token,
    );
  }

  Future<void> updateThemeMode({
    required String token,
    required ThemeMode mode,
  }) async {
    await _api.putJson(
      '/officer/preferences',
      {'theme_mode': mode.apiValue},
      token: token,
    );
  }
}

final officerWorkRepositoryProvider = Provider<OfficerWorkRepository>(
  (ref) => OfficerWorkRepository(ref.watch(apiClientProvider)),
);

// --- Data providers ----------------------------------------------------------

final allottedComplaintsProvider =
    FutureProvider.autoDispose<List<ComplaintSummary>>((ref) async {
  final session = ref.watch(officerSessionProvider);
  if (session == null) return [];
  return ref.read(officerWorkRepositoryProvider).allotted(
        token: session.token,
        officerId: session.officerId,
      );
});

final officerTrackProvider =
    FutureProvider.autoDispose<List<ComplaintSummary>>((ref) async {
  final session = ref.watch(officerSessionProvider);
  if (session == null) return [];
  return ref.read(officerWorkRepositoryProvider).jurisdiction(
        token: session.token,
        officerId: session.officerId,
      );
});

final officerProfileProvider =
    FutureProvider.autoDispose<OfficerProfile>((ref) async {
  final session = ref.watch(officerSessionProvider);
  if (session == null) {
    throw StateError('Not signed in');
  }
  final json = await ref.read(apiClientProvider).getJsonObject(
        '/officer/${session.officerId}/profile',
        token: session.token,
      );
  return OfficerProfile.fromJson(json);
});

/// Status history for a complaint, fetched with the officer's token.
final officerComplaintHistoryProvider = FutureProvider.autoDispose
    .family<List<ComplaintHistoryEntry>, String>((ref, complaintId) async {
  final session = ref.watch(officerSessionProvider);
  if (session == null) return [];
  return ref.read(trackRepositoryProvider).fetchHistory(
        token: session.token,
        complaintId: complaintId,
      );
});
