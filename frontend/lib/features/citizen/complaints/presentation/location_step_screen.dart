import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/step_progress_indicator.dart';
import '../../auth/application/session_controller.dart';
import '../application/complaint_draft_controller.dart';
import '../application/location_service.dart';
import '../data/complaint_repository.dart';
import '../data/complaint_storage.dart';
import '../data/department_catalog.dart';
import 'complaint_confirmation_screen.dart';

/// Step 3 of 3 — capture the complaint's location, choose a department, and
/// submit. This is the final step: on submit it uploads photos, registers the
/// complaint, and routes it to an officer via the backend.
class LocationStepScreen extends ConsumerStatefulWidget {
  const LocationStepScreen({super.key});

  @override
  ConsumerState<LocationStepScreen> createState() => _LocationStepScreenState();
}

class _LocationStepScreenState extends ConsumerState<LocationStepScreen> {
  final MapController _map = MapController();

  LatLng? _point;
  String? _address;
  String? _departmentId;
  bool _fetching = false;
  bool _submitting = false;
  bool _adjusting = false;
  LatLng _adjustCenter = const LatLng(13.0827, 80.2707); // Chennai fallback

  @override
  void initState() {
    super.initState();
    final draft = ref.read(complaintDraftProvider);
    if (draft.hasLocation) {
      _point = LatLng(draft.lat!, draft.lon!);
      _address = draft.addressLabel;
    }
    _departmentId = draft.departmentId;
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _fetching = true);
    try {
      final service = ref.read(locationServiceProvider);
      final pos = await service.getCurrentPosition();
      final address = await service.reverseGeocode(pos);
      if (!mounted) return;
      final point = LatLng(pos.lat, pos.lon);
      setState(() {
        _point = point;
        _address = address;
      });
      ref.read(complaintDraftProvider.notifier).setLocation(
            lat: pos.lat,
            lon: pos.lon,
            addressLabel: address,
          );
      _map.move(point, 16);
    } on LocationFailure catch (e) {
      if (e.permanentlyDenied) {
        _showPermissionDialog(e.message);
      } else {
        _snack(e.message);
      }
    } catch (_) {
      _snack('Couldn’t get your location. Please try again.');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _showPermissionDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location access needed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _startAdjusting() {
    setState(() {
      _adjusting = true;
      _adjustCenter = _point!;
    });
  }

  Future<void> _confirmAdjusting() async {
    final point = _adjustCenter;
    setState(() {
      _adjusting = false;
      _point = point;
      _address = null; // re-resolve for the new point
    });
    ref.read(complaintDraftProvider.notifier).setLocation(
          lat: point.latitude,
          lon: point.longitude,
        );
    final address =
        await ref.read(locationServiceProvider).reverseGeocode(
              LatLngPoint(point.latitude, point.longitude),
            );
    if (!mounted) return;
    setState(() => _address = address);
    ref.read(complaintDraftProvider.notifier).setLocation(
          lat: point.latitude,
          lon: point.longitude,
          addressLabel: address,
        );
  }

  void _selectDepartment(String id) {
    setState(() => _departmentId = id);
    ref.read(complaintDraftProvider.notifier).setDepartment(id);
  }

  bool get _canSubmit =>
      _point != null && _departmentId != null && !_submitting && !_adjusting;

  Future<void> _submit() async {
    final draft = ref.read(complaintDraftProvider);
    final session = ref.read(sessionControllerProvider);
    if (session == null || _point == null || _departmentId == null) return;

    setState(() => _submitting = true);
    try {
      // 1. Upload Step-1 photos to storage, collecting their URLs.
      final urls =
          await ref.read(complaintStorageProvider).uploadPhotos(draft.photos);

      // 2. Register the complaint (backend routes it to an officer).
      final result = await ref.read(complaintRepositoryProvider).register(
            token: session.token,
            departmentId: _departmentId!,
            descriptionText: draft.description.trim(),
            inputMode: draft.inputMode,
            imageUrls: urls,
            lat: _point!.latitude,
            lon: _point!.longitude,
            addressLabel: _address,
          );

      // 3. Clear the draft and show confirmation.
      ref.read(complaintDraftProvider.notifier).clear();
      if (!mounted) return;
      context.go(
        AppRoutes.complaintConfirmation,
        extra: ComplaintConfirmationArgs(
          complaintId: result.complaintId,
          unassigned: result.unassigned,
        ),
      );
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (e, st) {
      // Surface the real cause (e.g. Supabase not initialized, missing storage
      // bucket) instead of a generic message, so failures are diagnosable.
      debugPrint('Complaint submit failed: $e\n$st');
      _snack('Couldn’t submit: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register Complaint')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: StepProgressIndicator(
                currentStep: 3,
                totalSteps: 3,
                label: 'Location',
              ),
            ),
            Expanded(
              child: _point == null
                  ? _EmptyLocationState(
                      fetching: _fetching,
                      onUseCurrent: _useCurrentLocation,
                    )
                  : _LocationDetail(
                      map: _map,
                      point: _point!,
                      address: _address,
                      adjusting: _adjusting,
                      departmentId: _departmentId,
                      onStartAdjust: _startAdjusting,
                      onConfirmAdjust: _confirmAdjusting,
                      onAdjustCenterChanged: (c) => _adjustCenter = c,
                      onSelectDepartment: _selectDepartment,
                    ),
            ),
            if (_point != null && !_adjusting)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: PrimaryButton(
                      label: 'Submit Complaint',
                      icon: Icons.send_outlined,
                      isLoading: _submitting,
                      onPressed: _canSubmit ? _submit : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- Empty state ------------------------------------------------------------

class _EmptyLocationState extends StatelessWidget {
  const _EmptyLocationState({
    required this.fetching,
    required this.onUseCurrent,
  });

  final bool fetching;
  final VoidCallback onUseCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_on_outlined,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: AppSpacing.lg),
          Text('Where is the issue?',
              style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'We’ll capture your GPS location so the complaint reaches the right '
            'ward officer. You can fine-tune the pin afterwards.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: PrimaryButton(
                label: 'Use My Current Location',
                icon: Icons.my_location,
                isLoading: fetching,
                onPressed: onUseCurrent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Location detail (map + address + department) ---------------------------

class _LocationDetail extends StatelessWidget {
  const _LocationDetail({
    required this.map,
    required this.point,
    required this.address,
    required this.adjusting,
    required this.departmentId,
    required this.onStartAdjust,
    required this.onConfirmAdjust,
    required this.onAdjustCenterChanged,
    required this.onSelectDepartment,
  });

  final MapController map;
  final LatLng point;
  final String? address;
  final bool adjusting;
  final String? departmentId;
  final VoidCallback onStartAdjust;
  final VoidCallback onConfirmAdjust;
  final ValueChanged<LatLng> onAdjustCenterChanged;
  final ValueChanged<String> onSelectDepartment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;

        final mapWidget = ClipRRect(
          borderRadius: AppRadius.lgAll,
          child: SizedBox(
            height: wide ? 320 : 240,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: map,
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 16,
                    interactionOptions: InteractionOptions(
                      flags: adjusting
                          ? InteractiveFlag.all
                          : InteractiveFlag.none,
                    ),
                    onPositionChanged: (camera, hasGesture) {
                      if (adjusting) onAdjustCenterChanged(camera.center);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.civicroute',
                    ),
                    if (!adjusting)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: point,
                            width: 44,
                            height: 44,
                            alignment: Alignment.topCenter,
                            child: Icon(
                              Icons.location_on,
                              size: 44,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                // In adjust mode, a fixed center pin: pan the map beneath it.
                if (adjusting)
                  IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 44),
                        child: Icon(
                          Icons.location_on,
                          size: 44,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );

        final addressAndDept = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (adjusting)
              _AdjustControls(onConfirm: onConfirmAdjust)
            else
              _AddressRow(address: address, onChange: onStartAdjust),
            const SizedBox(height: AppSpacing.xl),
            Text('Which department?', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Pick the service this issue belongs to.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final dept in kDepartments)
                  _DepartmentChip(
                    dept: dept,
                    selected: dept.id == departmentId,
                    onTap: () => onSelectDepartment(dept.id),
                  ),
              ],
            ),
          ],
        );

        if (wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: mapWidget,
                ),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  flex: 6,
                  child: addressAndDept,
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          children: [
            mapWidget,
            const SizedBox(height: AppSpacing.md),
            addressAndDept,
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.address, required this.onChange});

  final String? address;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.place_outlined,
            size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            address ?? 'Address not available — the pin location will be used.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        TextButton.icon(
          onPressed: onChange,
          icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
          label: const Text('Change'),
        ),
      ],
    );
  }
}

class _AdjustControls extends StatelessWidget {
  const _AdjustControls({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Drag the map to move the pin to the exact spot.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton.tonalIcon(
          onPressed: onConfirm,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Done'),
        ),
      ],
    );
  }
}

class _DepartmentChip extends StatelessWidget {
  const _DepartmentChip({
    required this.dept,
    required this.selected,
    required this.onTap,
  });

  final DepartmentOption dept;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surface,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              dept.icon,
              size: 18,
              color: selected ? scheme.onPrimaryContainer : scheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              dept.label,
              style: theme.textTheme.labelLarge?.copyWith(
                color:
                    selected ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
