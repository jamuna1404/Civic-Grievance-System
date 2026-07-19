import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/relative_time.dart';
import '../../citizen/complaints/data/complaint_models.dart';
import '../../citizen/complaints/data/complaint_status.dart';
import '../../citizen/complaints/presentation/widgets/photo_gallery.dart';
import '../../citizen/complaints/presentation/widgets/status_timeline.dart';
import '../application/officer_session_controller.dart';
import '../data/officer_work_repository.dart';
import 'widgets/status_update_control.dart';

/// Navigation args for the officer complaint detail.
class OfficerComplaintArgs {
  const OfficerComplaintArgs({
    required this.complaint,
    required this.canUpdateStatus,
  });

  final ComplaintSummary complaint;

  /// True on the Allotted tab (assigned complaints), false on Track (read-only).
  final bool canUpdateStatus;
}

/// Officer-facing complaint detail: citizen contact, photos, description,
/// location, status timeline, and (when allotted) the status-update control.
class OfficerComplaintDetailScreen extends ConsumerStatefulWidget {
  const OfficerComplaintDetailScreen({super.key, required this.args});

  final OfficerComplaintArgs args;

  @override
  ConsumerState<OfficerComplaintDetailScreen> createState() =>
      _OfficerComplaintDetailScreenState();
}

class _OfficerComplaintDetailScreenState
    extends ConsumerState<OfficerComplaintDetailScreen> {
  bool _submitting = false;

  ComplaintSummary get _c => widget.args.complaint;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _updateStatus(String newStatus, String remarks) async {
    final session = ref.read(officerSessionProvider);
    if (session == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(officerWorkRepositoryProvider).updateStatus(
            token: session.token,
            complaintId: _c.complaintId,
            newStatus: newStatus,
            remarks: remarks.isEmpty ? null : remarks,
          );
      // Refresh the lists + this complaint's history.
      ref.invalidate(allottedComplaintsProvider);
      ref.invalidate(officerTrackProvider);
      ref.invalidate(officerComplaintHistoryProvider(_c.complaintId));
      if (!mounted) return;
      _snack('Status updated.');
      context.pop();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ComplaintStatus.fromWire(_c.status);
    final dept = _c.department;
    final history = ref.watch(officerComplaintHistoryProvider(_c.complaintId));

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
                    Text('Submitted ${absoluteDate(_c.createdAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
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

    final citizenContact = _c.citizenName != null || _c.citizenPhone != null
        ? _CitizenContact(name: _c.citizenName, phone: _c.citizenPhone)
        : const SizedBox.shrink();

    final photos = _c.imageUrls.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Photos'),
              PhotoGallery(imageUrls: _c.imageUrls),
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
          child: Text(_c.descriptionText, style: theme.textTheme.bodyLarge),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );

    final location = _c.hasLocation
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Location'),
              _MiniMap(point: LatLng(_c.lat!, _c.lon!), address: _c.addressLabel),
              const SizedBox(height: AppSpacing.lg),
            ],
          )
        : const SizedBox.shrink();

    final timelineContent = history.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              e is ApiException ? e.message : 'Couldn’t load history.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              onPressed: () => ref.invalidate(
                officerComplaintHistoryProvider(_c.complaintId),
              ),
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
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg,
          ),
          child: timelineContent,
        ),
        if (widget.args.canUpdateStatus)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl,
            ),
            child: StatusUpdateControl(
              current: status,
              submitting: _submitting,
              onSubmit: _updateStatus,
            ),
          )
        else
          const SizedBox(height: AppSpacing.xxl),
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
                        citizenContact,
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
              citizenContact,
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

class _CitizenContact extends StatelessWidget {
  const _CitizenContact({this.name, this.phone});

  final String? name;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.lgAll,
        ),
        child: Row(
          children: [
            Icon(Icons.account_circle_outlined,
                size: 36, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name ?? 'Citizen', style: theme.textTheme.titleMedium),
                  if (phone != null)
                    Text(phone!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                ],
              ),
            ),
            if (phone != null)
              IconButton(
                tooltip: 'Copy phone',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: phone!));
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(content: Text('Phone number copied')),
                    );
                },
              ),
          ],
        ),
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
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md,
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

class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.point, required this.address});

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
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.civicroute',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: point,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.location_on,
                          size: 40, color: theme.colorScheme.error),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
        if (address != null && address!.trim().isNotEmpty)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: Text(address!, style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}
