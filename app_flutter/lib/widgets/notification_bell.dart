import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/api_client.dart';
import '../services/supabase_client.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final ApiClient _apiClient = ApiClient();
  final SupabaseService _supabaseService = SupabaseService();
  
  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  StreamSubscription? _realtimeSubscription;
  bool _isDropdownOpen = false;

  @override
  void initState() {
    super.initState();
    _fetchInitialNotifications();
    _subscribeToRealtimeNotifications();
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  // 1. Initial Load via REST API
  Future<void> _fetchInitialNotifications() async {
    try {
      final response = await _apiClient.get('/api/notifications');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _notifications = List<Map<String, dynamic>>.from(data['notifications']);
            _unreadCount = data['unread_count'] ?? 0;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching notifications: $e");
    }
  }

  // 2. Real-time Subscription via Supabase Realtime Stream (FR-6.1)
  void _subscribeToRealtimeNotifications() {
    final currentUser = _supabaseService.currentUser;
    if (currentUser == null) return;

    try {
      // Subscribe to changes filtered to user_id
      _realtimeSubscription = _supabaseService.client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', currentUser.id)
          .order('created_at', ascending: false)
          .listen((List<Map<String, dynamic>> updatedList) {
            if (!mounted) return;

            // Identify newly inserted notifications to trigger Toasts/Snackbars
            final oldIds = _notifications.map((n) => n['id']).toSet();
            
            for (var updatedNode in updatedList) {
              final id = updatedNode['id'];
              // If it's a new notification and unread
              if (!oldIds.contains(id) && updatedNode['read_at'] == null) {
                _triggerSnackbarIfHighPriority(updatedNode);
              }
            }

            // Calculate unread count from the streamed list
            final unread = updatedList.where((n) => n['read_at'] == null).length;

            setState(() {
              _notifications = updatedList;
              _unreadCount = unread;
            });
          });
      
      debugPrint("Subscribed to Supabase Realtime notifications for user: ${currentUser.id}");
    } catch (e) {
      debugPrint("Realtime subscription failed: $e");
    }
  }

  // 3. Snackbar for High Priority Alerts
  void _triggerSnackbarIfHighPriority(Map<String, dynamic> notification) {
    final message = (notification['message'] ?? '').toString();
    final lowerMessage = message.toLowerCase();

    // Check high priority keywords (assignment, SLA breach/escalation)
    bool isHighPriority = lowerMessage.contains('escalat') || 
                          lowerMessage.contains('breach') || 
                          lowerMessage.contains('critical') || 
                          lowerMessage.contains('assigned');

    if (isHighPriority && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFC2410C), # Deep Amber/Red
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'DISMISS',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  // 4. Mark notifications read on open
  Future<void> _markAllAsRead() async {
    final unreads = _notifications.where((n) => n['read_at'] == null).toList();
    if (unreads.isEmpty) return;

    for (var n in unreads) {
      try {
        final id = n['id'];
        // Call backend PATCH to update DB
        await _apiClient.patch('/api/notifications/$id/read');
      } catch (e) {
        debugPrint("Error marking notification $e read");
      }
    }
    
    // Refresh local count
    _fetchInitialNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Map<String, dynamic>>(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications, color: Colors.white, size: 28),
          if (_unreadCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                child: Text(
                  '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      tooltip: 'Notifications',
      onOpened: () {
        // Mark all read when dropdown opens
        _markAllAsRead();
      },
      offset: const Offset(0, 48),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (BuildContext context) {
        if (_notifications.isEmpty) {
          return [
            const PopupMenuItem<Map<String, dynamic>>(
              enabled: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Text(
                    'No notifications yet',
                    style: TextStyle(color: Colors.slate, fontSize: 13),
                  ),
                ),
              ),
            )
          ];
        }

        return _notifications.map((n) {
          final isRead = n['read_at'] != null;
          final message = n['message'] ?? '';
          
          return PopupMenuItem<Map<String, dynamic>>(
            value: n,
            child: Container(
              width: 320,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Blue indicator dot for unread
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0, right: 8.0),
                    child: Icon(
                      Icons.circle,
                      size: 8,
                      color: isRead ? Colors.transparent : const Color(0xFF0EA5E9),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          style: TextStyle(
                            color: isRead ? Colors.grey[400] : Colors.white,
                            fontSize: 13,
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTime(n['created_at']),
                          style: TextStyle(color: Colors.grey[500], fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList();
      },
    );
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final parsed = DateTime.parse(dateStr).toLocal();
      final diff = DateTime.now().difference(parsed);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }
}
