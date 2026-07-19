import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/relative_time.dart';
import '../data/complaint_models.dart';
import '../data/complaint_status.dart';
import '../data/track_repository.dart';
import 'widgets/photo_gallery.dart';
import 'widgets/status_timeline.dart';

/// Complaint detail — header, photos, description, location map, and the
/// vertical status-history timeline.
class ComplaintDetailScreen extends ConsumerWidget {
  const ComplaintDetailScreen({super.key, required this.complaint});

  final ComplaintSummary complaint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ComplaintStatus.fromWire(complaint.status);
    final dept = complaint.department;
    final history = ref.watch(complaintHistoryProvider(complaint.complaintId));

    final header = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(dept.icon,
                    color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dept.label, style: theme.textTheme.titleLarge),
                    Text(
                      'Submitted ${absoluteDate(complaint.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          StatusChip(status: status),
        ],
      ),
    );

    final photos = complaint.imageUrls.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Photos'),
              PhotoGallery(imageUrls: complaint.imageUrls),
              const SizedBox(height: AppSpacing.lg),
            ],
          )
        : const SizedBox.shrink();

    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Description'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text(
            complaint.descriptionText,
            style: theme.textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );

    final location = complaint.hasLocation
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Location'),
              _LocationMap(
                point: LatLng(complaint.lat!, complaint.lon!),
                address: complaint.addressLabel,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          )
        : const SizedBox.shrink();

    final timelineContent = history.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              err is ApiException
                  ? err.message
                  : 'Couldn’t load the status history.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              onPressed: () =>
                  ref.invalidate(complaintHistoryProvider(complaint.complaintId)),
            ),
          ],
        ),
      ),
      data: (entries) => StatusTimeline(history: entries),
    );

    final timelineSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Status timeline'),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          child: timelineContent,
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Complaint')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        header,
                        photos,
                        description,
                        location,
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(
                    child: timelineSection,
                  ),
                ),
              ],
            );
          }

          return ListView(
            children: [
              header,
              photos,
              description,
              location,
              timelineSection,
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _LocationMap extends StatelessWidget {
  const _LocationMap({required this.point, required this.address});

  final LatLng point;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ClipRRect(
            borderRadius: AppRadius.lgAll,
            child: SizedBox(
              height: 180,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 16,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.civicroute',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: Icon(Icons.location_on,
                            size: 40, color: theme.colorScheme.error),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (address != null && address!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(address!, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
