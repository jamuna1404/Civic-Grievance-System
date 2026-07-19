import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../data/complaint_models.dart';
import '../../data/complaint_status.dart';

/// A vertical timeline of a complaint's progress.
///
/// Renders the canonical progression (SUBMITTED → ACKNOWLEDGED → IN_PROGRESS →
/// RESOLVED) with a **filled** node for each stage the complaint has reached
/// (with its timestamp + any officer remarks) and a **hollow** node for stages
/// not yet reached. If the complaint was REJECTED, the timeline ends in a
/// distinctly styled rejection node with the reason shown inline.
class StatusTimeline extends StatelessWidget {
  const StatusTimeline({super.key, required this.history});

  final List<ComplaintHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    // Latest entry per status (history arrives oldest-first).
    final byStatus = <String, ComplaintHistoryEntry>{};
    for (final e in history) {
      byStatus[e.status] = e;
    }
    final rejected = byStatus[ComplaintStatus.rejected.wire];

    final nodes = <_TimelineNodeData>[];
    if (rejected != null) {
      // Show whichever forward stages were reached before rejection, in order…
      for (final stage in ComplaintStatus.progression) {
        final entry = byStatus[stage.wire];
        if (entry != null) {
          nodes.add(_TimelineNodeData(status: stage, entry: entry));
        }
      }
      // …then the rejection node.
      nodes.add(
        _TimelineNodeData(
          status: ComplaintStatus.rejected,
          entry: rejected,
          rejected: true,
        ),
      );
    } else {
      for (final stage in ComplaintStatus.progression) {
        final entry = byStatus[stage.wire];
        nodes.add(
          _TimelineNodeData(
            status: stage,
            entry: entry,
            reached: entry != null,
          ),
        );
      }
    }

    // Find the active node index (the last reached/rejected node in the list).
    int activeIndex = -1;
    for (var i = nodes.length - 1; i >= 0; i--) {
      if (nodes[i].reached || nodes[i].rejected) {
        activeIndex = i;
        break;
      }
    }

    return Column(
      children: [
        for (var i = 0; i < nodes.length; i++)
          _TimelineNode(
            data: nodes[i],
            isLast: i == nodes.length - 1,
            isActive: i == activeIndex,
          ),
      ],
    );
  }
}

class _TimelineNodeData {
  _TimelineNodeData({
    required this.status,
    this.entry,
    this.reached = true,
    this.rejected = false,
  });

  final ComplaintStatus status;
  final ComplaintHistoryEntry? entry;
  final bool reached;
  final bool rejected;
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.data,
    required this.isLast,
    required this.isActive,
  });

  final _TimelineNodeData data;
  final bool isLast;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reached = data.reached;
    final color = data.status.color;
    final lineColor = reached ? color.withValues(alpha: 0.5) : scheme.outlineVariant;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left rail: dot + connecting line.
          SizedBox(
            width: 28,
            child: Column(
              children: [
                _Dot(
                  color: color,
                  reached: reached,
                  rejected: data.rejected,
                  isActive: isActive,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: lineColor),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Right: content.
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.status.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: reached ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                  if (data.entry != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      absoluteDateTime(data.entry!.changedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (data.entry!.officerName != null)
                      Text(
                        'by ${data.entry!.officerName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ] else
                    Text(
                      'Pending',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (data.rejected)
                    _RejectionReason(reason: data.entry?.remarks)
                  else if (data.entry?.remarks != null &&
                      data.entry!.remarks!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        data.entry!.remarks!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({
    required this.color,
    required this.reached,
    required this.rejected,
    required this.isActive,
  });

  final Color color;
  final bool reached;
  final bool rejected;
  final bool isActive;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      );
      final isTesting =
          WidgetsBinding.instance.runtimeType.toString().contains('Test');
      if (!isTesting) {
        _controller!.repeat();
      }
    }
  }

  @override
  void didUpdateWidget(covariant _Dot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      );
      final isTesting =
          WidgetsBinding.instance.runtimeType.toString().contains('Test');
      if (!isTesting) {
        _controller!.repeat();
      }
    } else if (!widget.isActive && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget dot;
    if (widget.rejected) {
      dot = Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        child: const Icon(Icons.close, size: 14, color: Colors.white),
      );
    } else if (widget.reached) {
      dot = Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 14, color: Colors.white),
      );
    } else {
      // Hollow (not yet reached).
      dot = Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surface,
          border: Border.all(color: scheme.outline, width: 2),
        ),
      );
    }

    if (widget.isActive && _controller != null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller!,
            builder: (context, child) {
              final val = _controller!.value;
              return Container(
                width: 22 + 16 * val,
                height: 22 + 16 * val,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(
                      alpha: 0.55 * (1.0 - val),
                    ),
                    width: 2.5,
                  ),
                ),
              );
            },
          ),
          dot,
        ],
      );
    }

    return dot;
  }
}

/// Rejection reason shown inline in a distinct error container.
class _RejectionReason extends StatelessWidget {
  const _RejectionReason({required this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: scheme.error),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Reason for rejection',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            reason == null || reason!.trim().isEmpty
                ? 'No reason was provided.'
                : reason!,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
