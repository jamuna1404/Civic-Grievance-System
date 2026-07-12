import 'dart:convert';
import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../widgets/reusable_widgets.dart';

class ComplaintDetailScreen extends StatefulWidget {
  final String complaintId;
  const ComplaintDetailScreen({super.key, required this.complaintId});

  @override
  State<ComplaintDetailScreen> createState() => _ComplaintDetailScreenState();
}

class _ComplaintDetailScreenState extends State<ComplaintDetailScreen> {
  final ApiClient _apiClient = ApiClient();
  
  Map<String, dynamic>? _complaint;
  List<dynamic> _timelineEvents = [];
  String _summaryText = "Loading summary narrative...";
  
  bool _isLoadingComplaint = true;
  bool _isLoadingTimeline = true;
  bool _isLoadingSummary = true;

  @override
  void initState() {
    super.initState();
    _loadComplaintDetails();
    _loadTimeline();
    _loadSummary();
  }

  // 1. Load details (GET /api/complaints)
  Future<void> _loadComplaintDetails() async {
    try {
      final response = await _apiClient.get('/api/complaints');
      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body);
        final match = list.firstWhere(
          (c) => c['id'].toString() == widget.complaintId,
          orElse: () => null,
        );
        if (mounted) {
          setState(() {
            _complaint = match;
            _isLoadingComplaint = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading complaint details: $e");
      if (mounted) setState(() => _isLoadingComplaint = false);
    }
  }

  // 2. Load Timeline (GET /api/complaints/{id}/timeline)
  Future<void> _loadTimeline() async {
    try {
      final response = await _apiClient.get('/api/complaints/${widget.complaintId}/timeline');
      if (response.statusCode == 200) {
        final List<dynamic> events = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _timelineEvents = events;
            _isLoadingTimeline = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading timeline: $e");
      if (mounted) setState(() => _isLoadingTimeline = false);
    }
  }

  // 3. Load LLM Narrative Summary (GET /api/complaints/{id}/summary)
  Future<void> _loadSummary() async {
    try {
      final response = await _apiClient.get('/api/complaints/${widget.complaintId}/summary');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _summaryText = data['summary'] ?? "No summary narrative generated.";
            _isLoadingSummary = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _summaryText = "Narrative summary unavailable.";
            _isLoadingSummary = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading summary: $e");
      if (mounted) {
        setState(() {
          _summaryText = "Failed to load summary narrative.";
          _isLoadingSummary = false;
        });
      }
    }
  }

  // SLA countdown formatter (FR-4.4 / FR-5.4)
  String _getSLACountdown(String? deadlineStr) {
    if (deadlineStr == null) return "Calculating SLA Deadline...";
    try {
      final deadline = DateTime.parse(deadlineStr).toLocal();
      final now = DateTime.now();
      final diff = deadline.difference(now);
      
      if (diff.isNegative) {
        return "SLA BREACHED (${diff.inHours.abs()} hours overdue)";
      } else {
        final hours = diff.inHours;
        final minutes = diff.inMinutes % 60;
        return "$hours hours, $minutes minutes remaining";
      }
    } catch (_) {
      return "SLA Deadline calculations pending";
    }
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF1E293B);
    const primaryColor = Color(0xFF0EA5E9);

    if (_isLoadingComplaint) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    if (_complaint == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(backgroundColor: cardColor, elevation: 0),
        body: const Center(child: Text("Complaint details not found.", style: TextStyle(color: Colors.white))),
      );
    }

    final subcategory = _complaint!['subcategory'] ?? 'General Issue';
    final description = _complaint!['raw_text'] ?? _complaint!['transcribed_text'] ?? 'No text description';
    final status = _complaint!['status'] ?? 'registered';
    final deadlineStr = _complaint!['sla_deadline'];
    final priorityLabel = _complaint!['priority_label'] ?? 'Medium';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: const Text("Grievance Status", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Core info card
            Card(
              color: cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.between,
                      children: [
                        Text(
                          subcategory.toUpperCase(),
                          style: const TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        StatusChip(status: status),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text("CITIZEN DESCRIPTION", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. SLA Countdown Banner (FR-4.4)
            if (status != 'closed' && status != 'resolved') ...[
              Card(
                color: deadlineStr == null
                    ? Colors.slate[800]
                    : (_getSLACountdown(deadlineStr).contains('BREACHED') ? const Color(0xFF991B1B) : const Color(0xFF065F46)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.timer, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _getSLACountdown(deadlineStr),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // 3. Narrative summary (FR-4.9)
            const Text(
              "Explainable AI Recap",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Card(
              color: cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: _isLoadingSummary
                    ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2)))
                    : Text(
                        _summaryText,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // 4. Lifecycle timeline (FR-6.2)
            const Text(
              "Complaint Timeline",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 16),
            _isLoadingTimeline
                ? const Center(child: CircularProgressIndicator(color: primaryColor))
                : ComplaintTimeline(events: _timelineEvents),
          ],
        ),
      ),
    );
  }
}
