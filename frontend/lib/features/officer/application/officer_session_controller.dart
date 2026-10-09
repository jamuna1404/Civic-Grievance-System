import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_mode_provider.dart'
    show sharedPreferencesProvider;

/// The authenticated officer's session, or null when logged out.
class OfficerSession {
  const OfficerSession({
    required this.token,
    required this.fullName,
    required this.officerId,
    required this.status,
    this.managesTeam = false,
  });

  final String token;
  final String fullName;
  final String officerId;

  /// PENDING_VERIFICATION / ACTIVE / SUSPENDED.
  final String status;

  /// True if this officer has subordinates — shows the "Manage Team" tab.
  final bool managesTeam;
}

/// Holds the current officer session, persisted to SharedPreferences. Separate
/// from the citizen session so the two roles don't collide.
class OfficerSessionController extends Notifier<OfficerSession?> {
  static const _tokenKey = 'officer_session_token';
  static const _nameKey = 'officer_full_name';
  static const _idKey = 'officer_id';
  static const _statusKey = 'officer_status';
  static const _managesTeamKey = 'officer_manages_team';

  @override
  OfficerSession? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final token = prefs.getString(_tokenKey);
    final name = prefs.getString(_nameKey);
    final id = prefs.getString(_idKey);
    final status = prefs.getString(_statusKey);
    if (token == null || name == null || id == null || status == null) {
      return null;
    }
    return OfficerSession(
      token: token,
      fullName: name,
      officerId: id,
      status: status,
      managesTeam: prefs.getBool(_managesTeamKey) ?? false,
    );
  }

  Future<void> signIn({
    required String token,
    required String fullName,
    required String officerId,
    required String status,
    bool managesTeam = false,
  }) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_nameKey, fullName);
    await prefs.setString(_idKey, officerId);
    await prefs.setString(_statusKey, status);
    await prefs.setBool(_managesTeamKey, managesTeam);
    state = OfficerSession(
      token: token,
      fullName: fullName,
      officerId: officerId,
      status: status,
      managesTeam: managesTeam,
    );
  }

  Future<void> signOut() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_tokenKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_idKey);
    await prefs.remove(_statusKey);
    await prefs.remove(_managesTeamKey);
    state = null;
  }
}

final officerSessionProvider =
    NotifierProvider<OfficerSessionController, OfficerSession?>(
  OfficerSessionController.new,
);
