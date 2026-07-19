import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Riverpod state for the app's [ThemeMode] (Light / Dark / System).
///
/// The choice is persisted locally with SharedPreferences. In a later prompt
/// this will also sync to the `user_preferences` table; for now local storage
/// is the source of truth.

/// Provides the [SharedPreferences] instance. Overridden in `main()` with the
/// already-resolved instance so reads/writes are synchronous everywhere else.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be '
      'overridden in ProviderScope before use.'),
);

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _prefsKey = 'theme_mode';

  @override
  ThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return _decode(prefs.getString(_prefsKey));
  }

  /// Sets and persists the theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_prefsKey, _encode(mode));
  }

  static ThemeMode _decode(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}
