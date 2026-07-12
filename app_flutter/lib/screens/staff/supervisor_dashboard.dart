import 'dart:convert';
import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../widgets/reusable_widgets.dart';

class SupervisorDashboard extends StatefulWidget {
  const SupervisorDashboard({super.key});

  @override
  State<SupervisorDashboard> createState() => _SupervisorDashboardState();
}

class _SupervisorDashboardState extends State<SupervisorDashboard> {
  final ApiClient _apiClient = ApiClient();
  List<Map<String, dynamic>> _complaints = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllComplaints();
  }

  // 1. Fetch complaints in supervisor's zone (geographic zone filter resolved by JWT)
  Future<void> _loadAllComplaints() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.get('/api/complaints');
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _complaints = List<Map<String, dynamic>>.from(data);
        });
      } else {
        _showSnackBar("Failed to load complaints: ${response.statusCode}", Colors.redAccent);
      }
    } catch (e) {
      _showSnackBar("Error loading complaints: $e", Colors.redAccent);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 2. Perform FSM approval or rejection (FR-5.3 / FR-5.1)
  Future<void> _handleApprove(String complaintId) async {
    try {
      final response = await _apiClient.post('/api/complaints/$complaintId/approve', {
        "note": "Resolution approved by supervisor. Closing complaint."
      });
      if (response.statusCode == 200) {
        _showSnackBar("Complaint resolved resolution APPROVED. Closed successfully!", Colors.green);
        _loadAllComplaints();
      } else {
        _showSnackBar("Approval failed: ${response.body}", Colors.redAccent);
      }
    } catch (e) {
      _showSnackBar("Error executing approval: $e", Colors.redAccent);
    }
  }

  Future<void> _handleReject(String complaintId) async {
    try {
      final response = await _apiClient.post('/api/complaints/$complaintId/actions', {
        "action": "reject",
        "note": "Resolution rejected by supervisor. Returning to field officer."
      });
      if (response.statusCode == 200) {
        _showSnackBar("Resolution REJECTED. Complaint returned to In-Progress status.", Colors.orange);
        _loadAllComplaints();
      } else {
        _showSnackBar("Rejection failed: ${response.body}", Colors.redAccent);
      }
    } catch (e) {
      _showSnackBar("Error executing rejection: $e", Colors.redAccent);
    }
  }

  void _showSnackBar(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF1E293B);
    const primaryColor = Color(0xFF0EA5E9);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    // Analytics computation on list
    final totalCount = _complaints.length;
    final openCount = _complaints.where((c) => ['assigned', 'in_progress', 'escalated'].contains(c['status'])).length;
    final resolvedCount = _complaints.where((c) => c['status'] == 'resolved').length;
    final closedCount = _complaints.where((c) => c['status'] == 'closed').length;
    final escalatedCount = _complaints.where((c) => c['status'] == 'escalated').length;
    final escalationRate = totalCount > 0 ? (escalatedCount / totalCount * 100).toStringAsFixed(1) : '0.0';

    // Grouping queues
    final pendingApprovalQueue = _complaints.where((c) => c['status'] == 'resolved').toList();
    final escalationsQueue = _complaints.where((c) => c['status'] == 'escalated').toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Analytics Strip KPIs
            Row(
              children: [
                _buildKPICard("ACTIVE OPEN", "$openCount", Colors.orangeAccent),
                const SizedBox(width: 16),
                _buildKPICard("PENDING APPROVAL", "${pendingApprovalQueue.length}", primaryColor),
                const SizedBox(width: 16),
                _buildKPICard("CLOSED RESOLVED", "$closedCount", const Color(0xFF10B981)),
                const SizedBox(width: 16),
                _buildKPICard("ESCALATION RATE", "$escalationRate%", Colors.redAccent),
              ],
            ),
            const SizedBox(height: 24),

            // Tab view sections
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    Container(
                      alignment: Alignment.centerLeft,
                      child: const TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicatorColor: primaryColor,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.grey,
                        tabs: [
                          Tab(text: "Pending Approval Queue"),
                          Tab(text: "Escalated Violations"),
                          Tab(text: "All Zone Complaints"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildComplaintQueueList(pendingApprovalQueue, isApprovalQueue: true),
                          _buildComplaintQueueList(escalationsQueue),
                          _buildComplaintQueueList(_complaints),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKPICard(String title, String val, Color accentColor) {
    return Expanded(
      child: Card(
        color: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                val,
                style: TextStyle(color: accentColor, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComplaintQueueList(List<Map<String, dynamic>> queue, {bool isApprovalQueue = false}) {
    const cardColor = Color(0xFF1E293B);
    const primaryColor = Color(0xFF0EA5E9);

    if (queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.slate[600]),
            const SizedBox(height: 12),
            const Text("Queue is clean. No items in this section.", style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: queue.length,
      itemBuilder: (context, index) {
        final comp = queue[index];
        final id = comp['id'] ?? '';
        final description = comp['raw_text'] ?? comp['transcribed_text'] ?? 'No text description';
        final status = comp['status'] ?? 'registered';
        final subcategory = comp['subcategory'] ?? 'General';
        final score = comp['priority_score'] ?? 0;
        final label = comp['priority_label'] ?? 'Medium';
        final breakdown = comp['priority_breakdown'] ?? {};
        final resolvedImg = comp['resolved_image_url'] ?? '';
        final resolvedNote = comp['resolved_note'] ?? '';

        return Card(
          color: cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header details
                Row(
                  mainAxisAlignment: MainAxisAlignment.between,
                  children: [
                    Text(
                      subcategory.toUpperCase(),
                      style: const TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Row(
                      children: [
                        StatusChip(status: status),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text("PRIORITY: $score ($label)", style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(description, style: const TextStyle(color: Colors.white, fontSize: 14)),
                
                // If in approval queue, show evidence details (FR-5.2 / FR-5.3)
                if (isApprovalQueue && resolvedNote.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("OFFICER CLOSING EVIDENCE", style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text("Note: $resolvedNote", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        if (resolvedImg.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(resolvedImg, height: 140, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
                              return Text("Image url: $resolvedImg", style: TextStyle(color: Colors.blue[300], fontSize: 12));
                            }),
                          ),
                        ]
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // FR-6.3: Expandable Priority Score Breakdown Transparency panel
                ExpansionTile(
                  title: const Text("Priority Score Breakdown Details", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  childrenPadding: const EdgeInsets.all(12),
                  iconColor: primaryColor,
                  collapsedIconColor: Colors.grey,
                  children: [
                    _buildBreakdownRow("Base Weight Points", breakdown['base_weight_points']),
                    _buildBreakdownRow("Keyword Boost Points", breakdown['keyword_boost_points']),
                    _buildBreakdownRow("Computer Vision Boost Points", breakdown['cv_boost_points']),
                    _buildBreakdownRow("Spatial Clustering Duplicate Boost", breakdown['cluster_boost_points']),
                    _buildBreakdownRow("SLA Decay Points", breakdown['sla_decay_points']),
                    const Divider(color: Colors.slate),
                    _buildBreakdownRow("Total Priority Score", score, isBold: true),
                  ],
                ),
                const SizedBox(height: 16),

                // Supervisor Actions
                if (isApprovalQueue)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _handleReject(id),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        icon: const Icon(Icons.close, color: Colors.redAccent),
                        label: const Text("REJECT & REOPEN", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => _handleApprove(id),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: const Text("APPROVE & CLOSE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBreakdownRow(String label, dynamic val, {bool isBold = false}) {
    final style = TextStyle(
      color: isBold ? Colors.white : Colors.grey[400],
      fontSize: 12,
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.between,
        children: [
          Text(label, style: style),
          Text("${val ?? 0}", style: style),
        ],
      ),
    );
  }
}
