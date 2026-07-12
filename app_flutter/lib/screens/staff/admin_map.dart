import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong2.dart';

import '../../services/api_client.dart';
import '../citizen/complaint_detail_screen.dart';

class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({super.key});

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  final ApiClient _apiClient = ApiClient();
  final MapController _mapController = MapController();

  List<Map<String, dynamic>> _allComplaints = [];
  List<Map<String, dynamic>> _filteredComplaints = [];
  List<Map<String, dynamic>> _jurisdictions = [];
  Map<String, dynamic> _stats = {
    "total_this_month": 0,
    "top_departments": [],
    "top_wards": []
  };

  bool _isLoading = true;

  // Filter properties
  String _selectedDepartment = "All";
  String _selectedStatus = "All";
  DateTime? _startDate;
  DateTime? _endDate;

  List<String> _departmentsList = ["All"];
  final List<String> _statusesList = ["All", "registered", "assigned", "in_progress", "resolved", "closed", "escalated"];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // Load all geodata, complaints lists, and stats
  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch complaints
      final complaintsResp = await _apiClient.get('/api/complaints');
      List<Map<String, dynamic>> tempComplaints = [];
      if (complaintsResp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(complaintsResp.body);
        tempComplaints = List<Map<String, dynamic>>.from(data);
      }

      // 2. Fetch admin jurisdictions boundaries
      final jurisResp = await _apiClient.get('/api/admin/jurisdictions');
      List<Map<String, dynamic>> tempJurisdictions = [];
      if (jurisResp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(jurisResp.body);
        tempJurisdictions = List<Map<String, dynamic>>.from(data);
      }

      // 3. Fetch admin summary stats
      final statsResp = await _apiClient.get('/api/admin/stats');
      Map<String, dynamic> tempStats = {
        "total_this_month": 0,
        "top_departments": [],
        "top_wards": []
      };
      if (statsResp.statusCode == 200) {
        tempStats = Map<String, dynamic>.from(jsonDecode(statsResp.body));
      }

      // Extract unique departments for dropdown
      final deptsSet = {"All"};
      for (var c in tempComplaints) {
        if (c['category'] != null) deptsSet.add(c['category'].toString());
      }

      setState(() {
        _allComplaints = tempComplaints;
        _jurisdictions = tempJurisdictions;
        _stats = tempStats;
        _departmentsList = deptsSet.toList();
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      debugPrint("Error loading admin dashboard: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading admin dashboard: $e"), backgroundColor: Colors.redAccent),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // Apply client-side filters instantly
  void _applyFilters() {
    setState(() {
      _filteredComplaints = _allComplaints.where((c) {
        // Department Filter
        if (_selectedDepartment != "All" && c['category'] != _selectedDepartment) {
          return false;
        }
        // Status Filter
        if (_selectedStatus != "All" && c['status'] != _selectedStatus) {
          return false;
        }
        // Date Range Filter
        if (c['created_at'] != null) {
          try {
            final date = DateTime.parse(c['created_at'].toString());
            if (_startDate != null && date.isBefore(_startDate!)) return false;
            if (_endDate != null && date.isAfter(_endDate!.add(const Duration(days: 1)))) return false;
          } catch (_) {}
        }
        return true;
      }).toList();
    });
  }

  // Parse GeoJSON coordinates to LatLng polygon points
  List<LatLng> _parsePolygon(String? geojsonStr) {
    if (geojsonStr == null) return [];
    try {
      final geojson = jsonDecode(geojsonStr);
      final type = geojson['type'];
      final List<LatLng> pts = [];
      
      if (type == "Polygon") {
        final List<dynamic> coords = geojson['coordinates'][0];
        for (var pair in coords) {
          pts.add(LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()));
        }
      } else if (type == "MultiPolygon") {
        // Just take the first polygon for preview simplification
        final List<dynamic> coords = geojson['coordinates'][0][0];
        for (var pair in coords) {
          pts.add(LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()));
        }
      }
      return pts;
    } catch (e) {
      debugPrint("Error parsing geojson: $e");
      return [];
    }
  }

  // Return colored warning fill depending on unresolved count
  Color _getPolygonColor(int openCount) {
    if (openCount == 0) return const Color(0x3310B981); // translucent green
    if (openCount <= 2) return const Color(0x33F59E0B); // translucent amber
    return const Color(0x33EF4444); // translucent red
  }

  // Return marker color by priority
  Color _getMarkerColor(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'critical': return Colors.redAccent;
      case 'high': return Colors.orangeAccent;
      case 'medium': return Colors.yellowAccent;
      case 'low': return Colors.greenAccent;
      default: return Colors.skyBlueAccent;
    }
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

    // Build Polygons layer (FR-8.2)
    final polygons = _jurisdictions.map((j) {
      final pts = _parsePolygon(j['geojson']);
      return Polygon(
        points: pts,
        color: _getPolygonColor(j['open_count'] ?? 0),
        borderColor: Colors.slate[400]!,
        borderStrokeWidth: 1.5,
        isFilled: true,
      );
    }).where((p) => p.points.isNotEmpty).toList();

    // Build Markers layer (FR-8.2)
    final markers = _filteredComplaints.where((c) => c['location_lat'] != null && c['location_lng'] != null).map((c) {
      final double lat = (c['location_lat'] as num).toDouble();
      final double lng = (c['location_lng'] as num).toDouble();
      final String priority = c['priority_label'] ?? 'Medium';
      final String id = c['id'] ?? '';

      return Marker(
        point: LatLng(lat, lng),
        width: 32,
        height: 32,
        child: GestureDetector(
          onTap: () {
            // Open tappable detail view
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ComplaintDetailScreen(complaintId: id)),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: _getMarkerColor(priority),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: const Icon(Icons.location_on, color: Colors.black87, size: 18),
          ),
        ),
      );
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left side - Map View (75%)
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                // Leaflet map widget with OpenStreetMap tiles (FR-8.2)
                FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: LatLng(13.0827, 80.2707), // Seed center of Chennai
                    initialZoom: 12.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.civicroute.app',
                    ),
                    PolygonLayer(polygons: polygons),
                    MarkerLayer(markers: markers),
                  ],
                ),

                // Floating Filter Bar overlay
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: cardColor.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                    ),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Department selector
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("Dept: ", style: TextStyle(color: Colors.grey, fontSize: 13)),
                            DropdownButton<String>(
                              value: _selectedDepartment,
                              dropdownColor: cardColor,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              underline: const SizedBox(),
                              items: _departmentsList.map((d) {
                                return DropdownMenuItem(value: d, child: Text(d));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedDepartment = val);
                                  _applyFilters();
                                }
                              },
                            )
                          ],
                        ),

                        // Status selector
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("Status: ", style: TextStyle(color: Colors.grey, fontSize: 13)),
                            DropdownButton<String>(
                              value: _selectedStatus,
                              dropdownColor: cardColor,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              underline: const SizedBox(),
                              items: _statusesList.map((s) {
                                return DropdownMenuItem(value: s, child: Text(s));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedStatus = val);
                                  _applyFilters();
                                }
                              },
                            )
                          ],
                        ),

                        // Date Pickers
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2025),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setState(() => _startDate = picked);
                              _applyFilters();
                            }
                          },
                          icon: const Icon(Icons.date_range, color: primaryColor, size: 16),
                          label: Text(
                            _startDate == null ? "Start Date" : "${_startDate!.day}/${_startDate!.month}",
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                        
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2025),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setState(() => _endDate = picked);
                              _applyFilters();
                            }
                          },
                          icon: const Icon(Icons.date_range, color: primaryColor, size: 16),
                          label: Text(
                            _endDate == null ? "End Date" : "${_endDate!.day}/${_endDate!.month}",
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),

                        // Clear filters button
                        IconButton(
                          icon: const Icon(Icons.clear, color: Colors.redAccent, size: 20),
                          tooltip: "Clear Filters",
                          onPressed: () {
                            setState(() {
                              _selectedDepartment = "All";
                              _selectedStatus = "All";
                              _startDate = null;
                              _endDate = null;
                            });
                            _applyFilters();
                          },
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Right side - Stats/Analytics Panel (25%)
          Expanded(
            flex: 1,
            child: Container(
              color: cardColor,
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "ADMIN METRICS PANEL",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                    ),
                    const Divider(color: Colors.slate, height: 24),

                    // Metric 1: Monthly Volume
                    const Text("VOLUME THIS MONTH", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      "${_stats['total_this_month'] ?? 0}",
                      style: const TextStyle(color: primaryColor, fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),

                    // Metric 2: Top Departments
                    const Text("TOP DEPARTMENTS (VOLUME)", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...(_stats['top_departments'] as List<dynamic> ?? []).map((d) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.between,
                          children: [
                            Expanded(
                              child: Text(
                                d['name'].toString(),
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ),
                            Text(
                              "${d['count']}",
                              style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 24),

                    // Metric 3: Top Wards by Escalation
                    const Text("TOP ESCALATION WARDS", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...(_stats['top_wards'] as List<dynamic> ?? []).map((w) {
                      final double rate = (w['rate'] as num).toDouble();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.between,
                          children: [
                            Text(
                              w['ward'].toString(),
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                            Text(
                              "${rate.toStringAsFixed(1)}% rate",
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
