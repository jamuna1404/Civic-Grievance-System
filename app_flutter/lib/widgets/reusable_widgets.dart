import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'registered': return const Color(0xFF0EA5E9); # Sky blue
      case 'assigned': return const Color(0xFFF59E0B); # Amber
      case 'in_progress': return const Color(0xFF8B5CF6); # Violet
      case 'resolved': return const Color(0xFF10B981); # Emerald
      case 'closed': return const Color(0xFF64748B); # Slate
      case 'escalated': return const Color(0xFFEF4444); # Red
      default: return const Color(0xFF94A3B8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class ComplaintTimeline extends StatelessWidget {
  final List<dynamic> events;
  const ComplaintTimeline({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24.0),
          child: Text(
            "No events logged yet.",
            style: TextStyle(color: Colors.slate, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final action = (event['action'] ?? '').toString().replaceAll('_', ' ');
        final note = (event['note'] ?? '').toString();
        final createdAtStr = (event['created_at'] ?? '').toString();
        
        String timeDisplay = createdAtStr;
        try {
          final dt = DateTime.parse(createdAtStr).toLocal();
          timeDisplay = "${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
        } catch (_) {}

        final isLast = index == events.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0F172A), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0EA5E9).withOpacity(0.4),
                        blurRadius: 4,
                      )
                    ],
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 55,
                    color: const Color(0xFF334155),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      note,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    timeDisplay,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
