import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../citizen/complaints/data/complaint_models.dart';
import '../data/officer_work_repository.dart';
import 'officer_session_controller.dart';

/// A live closure-request alert to surface as an in-app banner. Holds the full
/// complaint so tapping the banner can open its review detail without a fetch.
class ClosureRequestAlert {
  const ClosureRequestAlert(this.complaint);
  final ComplaintSummary complaint;
}

/// Subscribes (only while a team-managing officer has an active, foregrounded
/// session) to Supabase Realtime UPDATE events on `complaints`, and raises a
/// [ClosureRequestAlert] when a complaint in this officer's boundary scope
/// flips to RESOLUTION_REQUESTED.
///
/// This is a convenience layer only: the same items always appear at the top
/// of the Manage Team list. Scoped to exactly this one notification case — not
/// a general notification system.
class OfficerRealtimeController extends Notifier<ClosureRequestAlert?> {
  RealtimeChannel? _channel;
  AppLifecycleListener? _lifecycle;
  List<int> _scope = const [];
  OfficerSession? _session;

  @override
  ClosureRequestAlert? build() {
    final session = ref.watch(officerSessionProvider);
    _session = session;
    // Rebuild (session change) or provider disposal tears the channel down —
    // covers logout and officer switch.
    ref.onDispose(_disposeAll);

    if (session != null && session.managesTeam && _supabaseReady) {
      _lifecycle ??= AppLifecycleListener(
        onPause: _teardownChannel, // app backgrounded
        onResume: _subscribeChannel, // app foregrounded again
      );
      _start(session);
    }
    return null;
  }

  bool get _supabaseReady {
    try {
      Supabase.instance.client; // throws if not initialized
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _start(OfficerSession session) async {
    try {
      _scope = await ref
          .read(officerWorkRepositoryProvider)
          .teamBoundaryScope(token: session.token, officerId: session.officerId);
    } catch (_) {
      _scope = const [];
    }
    _subscribeChannel();
  }

  void _subscribeChannel() {
    final session = _session;
    if (session == null || _channel != null) return;
    _channel = Supabase.instance.client
        .channel('closure-requests-${session.officerId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'complaints',
          callback: _onComplaintUpdate,
        )
        .subscribe();
  }

  Future<void> _onComplaintUpdate(PostgresChangePayload payload) async {
    final row = payload.newRecord;
    if (row['status'] != 'RESOLUTION_REQUESTED') return;
    final boundaryId = row['resolved_boundary_id'];
    if (boundaryId is! int || !_scope.contains(boundaryId)) return;

    // Refresh the Manage Team list and pull the full row (officer name, etc.)
    // for the banner text and the tap-through navigation target.
    try {
      final list = await ref.refresh(teamComplaintsProvider.future);
      final complaintId = row['complaint_id'];
      for (final c in list) {
        if (c.complaintId == complaintId) {
          state = ClosureRequestAlert(c);
          return;
        }
      }
    } catch (_) {
      // Realtime is best-effort; the list still shows the item on next view.
    }
  }

  /// Clear the alert once the banner has been shown (so it fires once).
  void consume() => state = null;

  void _teardownChannel() {
    final channel = _channel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
      _channel = null;
    }
  }

  void _disposeAll() {
    _teardownChannel();
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}

final officerRealtimeProvider =
    NotifierProvider<OfficerRealtimeController, ClosureRequestAlert?>(
  OfficerRealtimeController.new,
);
