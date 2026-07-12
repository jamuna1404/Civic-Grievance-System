import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen.dart';
import '../widgets/notification_bell.dart';
import 'citizen/my_complaints_screen.dart';
import 'staff/officer_dashboard.dart';
import 'staff/supervisor_dashboard.dart';
import 'staff/admin_map.dart';





class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  User? _user;
  String _role = "citizen";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final sessionUser = _supabase.auth.currentUser;
    if (sessionUser == null) {
      _redirectToLogin();
      return;
    }

    setState(() {
      _user = sessionUser;
    });

    try {
      // Query the database to get the user's role from the 'users' table
      final response = await _supabase
          .from('users')
          .select('role')
          .eq('id', sessionUser.id)
          .maybeSingle();

      if (response != null && response['role'] != null) {
        setState(() {
          _role = response['role'];
        });
      }
    } catch (e) {
      // Fallback if local table user record is not synced yet
      debugPrint("Error fetching user role: ${e.toString()}");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _redirectToLogin() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  }

  Future<void> _handleSignOut() async {
    await _supabase.auth.signOut();
    _redirectToLogin();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0EA5E9))),
      );
    }

    final theme = Theme.of(context);
    const backgroundColor = Color(0xFF0F172A);
    const cardColor = Color(0xFF1E293B);
    const primaryColor = Color(0xFF0EA5E9);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: const Text('CivicRoute Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          const NotificationBell(),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _handleSignOut,
            tooltip: 'Logout',
          )
        ],

      ),
      body: _role == "officer"
          ? const OfficerDashboard()
          : (_role == "supervisor"
              ? const SupervisorDashboard()
              : (_role == "admin"
                  ? const AdminMapScreen()
                  : Padding(
                      padding: const EdgeInsets.all(24.0),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // User Welcome Info
                      Card(
                        color: cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: primaryColor.withOpacity(0.2),
                                radius: 28,
                                child: const Icon(Icons.person, color: primaryColor, size: 28),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _user?.email ?? 'User',
                                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _role.toUpperCase(),
                                        style: const TextStyle(color: primaryColor, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    )
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Main Dashboard Workspace placeholder
                      Expanded(
                        child: Card(
                          color: cardColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _role == "citizen" ? Icons.add_photo_alternate_outlined : Icons.queue_play_next_outlined,
                                  size: 80,
                                  color: Colors.slate[500],
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  _role == "citizen" 
                                      ? 'Submit a New Complaint'
                                      : 'Grievance Assigned Queue',
                                  style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _role == "citizen"
                                      ? 'Report issues like potholes, water leakage, or broken streetlights with location, photos, and voice.'
                                      : 'Access citizens complaints resolved to your department and ward to update their status.',
                                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[400]),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 28),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    if (_role == "citizen") {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => const MyComplaintsScreen()),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Staff portal views are coming in the next prompt.'),
                                          backgroundColor: primaryColor,
                                        ),
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: Icon(_role == "citizen" ? Icons.add : Icons.list_alt, color: Colors.white),
                                  label: Text(
                                    _role == "citizen" ? 'File Grievance' : 'Open Queue',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                )
                              ],
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                ))),

    );
  }
}
