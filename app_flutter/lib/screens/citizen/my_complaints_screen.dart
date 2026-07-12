import 'dart:convert';
import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../widgets/reusable_widgets.dart';
import 'complaint_detail_screen.dart';
import 'new_complaint_screen.dart';

class MyComplaintsScreen extends StatefulWidget {
  const MyComplaintsScreen({super.key});

  @override
  State<MyComplaintsScreen> createState() => _MyComplaintsScreenState();
}

class _MyComplaintsScreenState extends State<MyComplaintsScreen> {
  final ApiClient _apiClient = ApiClient();
  List<Map<String, dynamic>> _complaints = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadComplaints();
  }

  Future<void> _loadComplaints() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.get('/api/complaints');
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _complaints = List<Map<String, dynamic>>.from(data);
        });
      } else {
        _showSnackBar("Failed to load complaints: ${response.statusCode}");
      }
    } catch (e) {
      _showSnackBar("Error loading complaints: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF1E293B);
    const primaryColor = Color(0xFF0EA5E9);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: const Text("My Grievances", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : RefreshIndicator(
              onRefresh: _loadComplaints,
              color: primaryColor,
              child: _complaints.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.assignment_outlined, size: 80, color: Colors.slate[600]),
                              const SizedBox(height: 16),
                              const Text(
                                "No complaints filed yet",
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Tap the floating button below to report an issue.",
                                style: TextStyle(color: Colors.grey[400], fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _complaints.length,
                      itemBuilder: (context, index) {
                        final comp = _complaints[index];
                        final id = comp['id'] ?? '';
                        final description = comp['raw_text'] ?? comp['transcribed_text'] ?? 'No text description';
                        final status = comp['status'] ?? 'registered';
                        final subcategory = comp['subcategory'] ?? 'General Issue';
                        final dateStr = comp['created_at'] ?? '';
                        
                        String displayDate = dateStr;
                        try {
                          final dt = DateTime.parse(dateStr).toLocal();
                          displayDate = "${dt.day}/${dt.month}/${dt.year}";
                        } catch (_) {}

                        return Card(
                          color: cardColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.only(bottom: 14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ComplaintDetailScreen(complaintId: id),
                                ),
                              ).then((_) => _loadComplaints());
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.between,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          subcategory.toUpperCase(),
                                          style: const TextStyle(
                                            color: primaryColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      StatusChip(status: status),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.between,
                                    children: [
                                      Text(
                                        "ID: ${id.toString().substring(0, 8)}...",
                                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                      ),
                                      Text(
                                        displayDate,
                                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NewComplaintScreen()),
          ).then((refresh) {
            if (refresh == true) {
              _loadComplaints();
            }
          });
        },
        backgroundColor: primaryColor,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}
