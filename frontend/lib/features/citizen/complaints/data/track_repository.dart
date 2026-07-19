import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;
import 'complaint_models.dart';

/// Reads the citizen's complaints and their status history.
class TrackRepository {
  TrackRepository(this._api);

  final ApiClient _api;

  Future<List<ComplaintSummary>> fetchMyComplaints({
    required String token,
    required String citizenId,
  }) async {
    final data = await _api.getJsonList(
      '/citizen/$citizenId/complaints',
      token: token,
    );
    return data
        .map((e) => ComplaintSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ComplaintHistoryEntry>> fetchHistory({
    required String token,
    required String complaintId,
  }) async {
    final data = await _api.getJsonList(
      '/complaints/$complaintId/history',
      token: token,
    );
    return data
        .map((e) => ComplaintHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final trackRepositoryProvider = Provider<TrackRepository>(
  (ref) => TrackRepository(ref.watch(apiClientProvider)),
);

/// The logged-in citizen's complaints, newest first. Auto-disposed so it
/// refetches when the tab is revisited; call `ref.invalidate` to force refresh.
final myComplaintsProvider =
    FutureProvider.autoDispose<List<ComplaintSummary>>((ref) async {
  final session = ref.watch(sessionControllerProvider);
  if (session == null) return [];
  return ref.read(trackRepositoryProvider).fetchMyComplaints(
        token: session.token,
        citizenId: session.citizenId,
      );
});

/// Status history for a given complaint id.
final complaintHistoryProvider = FutureProvider.autoDispose
    .family<List<ComplaintHistoryEntry>, String>((ref, complaintId) async {
  final session = ref.watch(sessionControllerProvider);
  if (session == null) return [];
  return ref.read(trackRepositoryProvider).fetchHistory(
        token: session.token,
        complaintId: complaintId,
      );
});
