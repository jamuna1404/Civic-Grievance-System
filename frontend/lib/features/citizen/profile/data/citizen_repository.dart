import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart' show apiClientProvider;

/// Maps between Flutter's [ThemeMode] and the backend's
/// `user_preferences.theme_mode` enum (`LIGHT` / `DARK` / `SYSTEM`).
extension ThemeModeApi on ThemeMode {
  String get apiValue => switch (this) {
        ThemeMode.light => 'LIGHT',
        ThemeMode.dark => 'DARK',
        ThemeMode.system => 'SYSTEM',
      };

  static ThemeMode fromApi(String? value) => switch (value) {
        'LIGHT' => ThemeMode.light,
        'DARK' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// Talks to the authenticated citizen profile & preferences endpoints.
class CitizenRepository {
  CitizenRepository(this._api);

  final ApiClient _api;

  /// Updates the citizen's display name; returns the saved (trimmed) name.
  Future<String> updateName({
    required String token,
    required String fullName,
  }) async {
    final json = await _api.putJson(
      '/citizen/profile',
      {'full_name': fullName},
      token: token,
    );
    return json['full_name'] as String;
  }

  /// Persists the theme preference to `user_preferences`.
  Future<void> updateThemeMode({
    required String token,
    required ThemeMode mode,
  }) async {
    await _api.putJson(
      '/citizen/preferences',
      {'theme_mode': mode.apiValue},
      token: token,
    );
  }
}

final citizenRepositoryProvider = Provider<CitizenRepository>(
  (ref) => CitizenRepository(ref.watch(apiClientProvider)),
);
