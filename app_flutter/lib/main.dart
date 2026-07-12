import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load build-time environment constants (can be passed via --dart-define)
  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder-project.supabase.co',
  );
  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'placeholder-anon-key',
  );

  // Initialize Supabase SDK client (FR-6.1 / auth integration)
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const CivicRouteApp());
}

class CivicRouteApp extends StatelessWidget {
  const CivicRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Check if a session already exists to skip login
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'CivicRoute',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0EA5E9),
          brightness: Brightness.dark,
          background: const Color(0xFF0F172A),
        ),
      ),
      home: session != null ? const HomeScreen() : const AuthScreen(),
    );
  }
}
