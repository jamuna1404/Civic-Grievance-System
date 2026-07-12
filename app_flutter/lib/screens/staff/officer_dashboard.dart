import 'dart:convert';
import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../widgets/reusable_widgets.dart';

class OfficerDashboard extends StatefulWidget {
  const OfficerDashboard({super.key});

  @override
  State<OfficerDashboard> createState() => _OfficerDashboardState();
}

class _OfficerDashboardState extends State<OfficerDashboard> {
  final ApiClient _apiClient = ApiClient();
  List<Map<String, dynamic>> _complaints = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  // 1. Fetch complaints assigned to this officer (FR-4.3 / geographic filter resolved by JWT)
  Future<void> _loadQueue() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.get('/api/complaints');
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final list = List<Map<String, dynamic>>.from(data);
        
        // Sort: Priority Score (highest first) then SLA deadline (closest first)
        list.sort((a, b) {
          final scoreA = a['priority_score'] ?? 0;
          final scoreB = b['priority_score'] ?? 0;
          if (scoreA != scoreB) {
            return scoreB.compareTo(scoreA); // Highest priority score first
          }
          final deadlineA = a['sla_deadline'] ?? '';
          final deadlineB = b['sla_deadline'] ?? '';
          return deadlineA.compareTo(deadlineB); // Closest deadline first
        });

        setState(() {
          _complaints = list;
        });
      } else {
        _showSnackBar("Failed to load queue: ${response.statusCode}", Colors.redAccent);
      }
    } catch (e) {
      _showSnackBar("Error loading queue: $e", Colors.redAccent);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 2. Perform FSM transition action (Prompt 9 / FSM rules)
  Future<void> _handleAction(String complaintId, String action, {String? note, String? evidenceUrl}) async {
    try {
      final body = <String, dynamic>{
        "action": action,
      };
      if (note != null) body['note'] = note;
      if (evidenceUrl != null) body['evidence_image_url'] = evidenceUrl;

      final response = await _apiClient.post('/api/complaints/$complaintId/actions', body);
      if (response.statusCode == 200) {
        _showSnackBar("Action '$action' executed successfully!", Colors.green);
        _loadQueue();
      } else {
        final error = jsonDecode(response.body);
        _showSnackBar("Action failed: ${error['detail'] ?? response.body}", Colors.redAccent);
      }
    } catch (e) {
      _showSnackBar("Error executing action: $e", Colors.redAccent);
    }
  }

  // Open mark resolved dialog (FR-5.2 - requires evidence image + closing note)
  void _showResolveDialog(String complaintId) {
    final noteController = TextEditingController();
    final imgController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text("Resolve Complaint", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Resolve requires providing an evidence photograph URL and a closing description.",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Closing note/resolution note",
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: imgController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Evidence Photo URL (e.g. Supabase Storage link)",
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                final note = noteController.text.trim();
                final img = imgController.text.trim();
                if (note.isEmpty || img.isEmpty) {
                  _showSnackBar("Both closing note and evidence photograph URL are required.", Colors.amber);
                  return;
                }
                Navigator.of(context).pop();
                _handleAction(complaintId, "mark_resolved", note: note, evidenceUrl: img);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              child: const Text("RESOLVE", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
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

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : RefreshIndicator(
              onRefresh: _loadQueue,
              color: primaryColor,
              child: _complaints.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.checklist, size: 80, color: Colors.slate[600]),
                          const SizedBox(height: 16),
                          const Text("No complaints assigned to your jurisdiction.", style: TextStyle(color: Colors.white, fontSize: 16)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(24.0),
                      itemCount: _complaints.length,
                      itemBuilder: (context, index) {
                        final comp = _complaints[index];
                        final id = comp['id'] ?? '';
                        final description = comp['raw_text'] ?? comp['transcribed_text'] ?? 'No text description';
                        final status = comp['status'] ?? 'registered';
                        final subcategory = comp['subcategory'] ?? 'General';
                        final score = comp['priority_score'] ?? 0;
                        final label = comp['priority_label'] ?? 'Medium';
                        final breakdown = comp['priority_breakdown'] ?? {};

                        return Card(
                          color: cardColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header row
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

                                // Action Buttons
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (status == 'assigned')
                                      ElevatedButton.icon(
                                        onPressed: () => _handleAction(id, "start_work"),
                                        style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                                        icon: const Icon(Icons.play_arrow, color: Colors.white),
                                        label: const Text("START WORK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                    if (status == 'in_progress')
                                      ElevatedButton.icon(
                                        onPressed: () => _showResolveDialog(id),
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                                        icon: const Icon(Icons.check, color: Colors.white),
                                        label: const Text("MARK RESOLVED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                    if (status == 'resolved' || status == 'closed')
                                      const Text("COMPLETED", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
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
