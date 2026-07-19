import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';

/// Result of verifying an OTP.
class VerifyOtpResult {
  const VerifyOtpResult({
    required this.newUser,
    this.sessionToken,
    this.fullName,
    this.citizenId,
  });

  /// True when no citizen record exists yet — the caller must complete signup.
  final bool newUser;

  /// Present only for returning users (new users get a token after signup).
  final String? sessionToken;
  final String? fullName;
  final String? citizenId;
}

/// Result of a successful signup / login that yields a session.
class AuthSession {
  const AuthSession({
    required this.sessionToken,
    required this.fullName,
    required this.citizenId,
  });

  final String sessionToken;
  final String fullName;
  final String citizenId;
}

/// Talks to the citizen auth endpoints. Throws [ApiException] on failure.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// Requests a (dummy) OTP for [phoneNumber]. Returns the canonical E.164
  /// number the backend tied the OTP to.
  Future<String> sendOtp(String phoneNumber) async {
    final json = await _api.postJson(
      '/auth/citizen/send-otp',
      {'phone_number': phoneNumber},
    );
    return json['phone_number'] as String;
  }

  Future<VerifyOtpResult> verifyOtp(String phoneNumber, String otpCode) async {
    final json = await _api.postJson(
      '/auth/citizen/verify-otp',
      {'phone_number': phoneNumber, 'otp_code': otpCode},
    );
    return VerifyOtpResult(
      newUser: json['new_user'] as bool,
      sessionToken: json['session_token'] as String?,
      fullName: json['full_name'] as String?,
      citizenId: json['citizen_id'] as String?,
    );
  }

  Future<AuthSession> completeSignup(
    String phoneNumber,
    String fullName,
  ) async {
    final json = await _api.postJson(
      '/auth/citizen/complete-signup',
      {'phone_number': phoneNumber, 'full_name': fullName},
    );
    return AuthSession(
      sessionToken: json['session_token'] as String,
      fullName: json['full_name'] as String,
      citizenId: json['citizen_id'] as String,
    );
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.dispose);
  return client;
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);
