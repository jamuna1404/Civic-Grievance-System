import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_mode_provider.dart' show sharedPreferencesProvider;

/// The authenticated citizen's session, or null when logged out.
class CitizenSession {
  const CitizenSession({
    required this.token,
    required this.fullName,
    required this.phoneNumber,
    required this.citizenId,
  });

  final String token;
  final String fullName;

  /// Canonical E.164 number (`+91XXXXXXXXXX`). Shown read-only on the profile.
  final String phoneNumber;

  /// The citizen's UUID — used to fetch their complaints.
  final String citizenId;

  CitizenSession copyWith({String? fullName}) => CitizenSession(
        token: token,
        fullName: fullName ?? this.fullName,
        phoneNumber: phoneNumber,
        citizenId: citizenId,
      );
}

/// Holds the current citizen session and persists it to SharedPreferences so
/// the login survives app restarts.
///
/// For this milestone the token is stored as-is; migrating to secure storage
/// (flutter_secure_storage) is a later hardening step.
class SessionController extends Notifier<CitizenSession?> {
  static const _tokenKey = 'citizen_session_token';
  static const _nameKey = 'citizen_full_name';
  static const _phoneKey = 'citizen_phone_number';
  static const _idKey = 'citizen_id';

  @override
  CitizenSession? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final token = prefs.getString(_tokenKey);
    final name = prefs.getString(_nameKey);
    final phone = prefs.getString(_phoneKey);
    final id = prefs.getString(_idKey);
    if (token == null || name == null || phone == null || id == null) {
      return null;
    }
    return CitizenSession(
      token: token,
      fullName: name,
      phoneNumber: phone,
      citizenId: id,
    );
  }

  Future<void> signIn({
    required String token,
    required String fullName,
    required String phoneNumber,
    required String citizenId,
  }) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_nameKey, fullName);
    await prefs.setString(_phoneKey, phoneNumber);
    await prefs.setString(_idKey, citizenId);
    state = CitizenSession(
      token: token,
      fullName: fullName,
      phoneNumber: phoneNumber,
      citizenId: citizenId,
    );
  }

  /// Updates the cached display name after a profile edit.
  Future<void> updateName(String fullName) async {
    final current = state;
    if (current == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_nameKey, fullName);
    state = current.copyWith(fullName: fullName);
  }

  Future<void> signOut() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_tokenKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_phoneKey);
    await prefs.remove(_idKey);
    state = null;
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, CitizenSession?>(SessionController.new);
