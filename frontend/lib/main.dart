import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';

/// Reads a Supabase config value, preferring a bundled `.env` file and falling
/// back to a compile-time `--dart-define` of the same name. Use the ANON /
/// publishable key for [SUPABASE_ANON_KEY] — never the service_role key.
String _config(String key) {
  final fromEnv = dotenv.maybeGet(key);
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  return String.fromEnvironment(key);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the .env asset if present (ignored if missing so the app still runs
  // without it — e.g. when using --dart-define instead).
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // No .env bundled; fall back to --dart-define values.
  }

  final supabaseUrl = _config('SUPABASE_URL');
  final supabaseAnonKey = _config('SUPABASE_ANON_KEY');

  // Initialize Supabase only when configured, so the app still runs (auth via
  // the FastAPI backend, theming, etc.) during local development without keys.
  if (supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      supabaseAnonKey != 'PASTE_YOUR_ANON_PUBLIC_KEY_HERE') {
    await Supabase.initialize(
      url: supabaseUrl,
      // anonKey still accepts a project anon key; publishableKey is the newer
      // name for the same client-safe key slot.
      // ignore: deprecated_member_use
      anonKey: supabaseAnonKey,
    );
  }

  // Resolve SharedPreferences once up front so the theme provider (and future
  // preference providers) can read it synchronously.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const CivicRouteApp(),
    ),
  );
}

class CivicRouteApp extends ConsumerWidget {
  const CivicRouteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'CivicRoute',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
