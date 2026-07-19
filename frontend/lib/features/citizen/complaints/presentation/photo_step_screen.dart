import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/step_progress_indicator.dart';
import '../application/complaint_draft_controller.dart';

/// Injectable so widget tests can provide a fake picker.
final imagePickerProvider = Provider<ImagePicker>((ref) => ImagePicker());

/// Step 1 of 3 — attach one or more photos of the civic issue.
///
/// Photos are kept only in [complaintDraftProvider] (in-memory) until final
/// submit; nothing is uploaded here.
class PhotoStepScreen extends ConsumerStatefulWidget {
  const PhotoStepScreen({super.key});

  @override
  ConsumerState<PhotoStepScreen> createState() => _PhotoStepScreenState();
}

class _PhotoStepScreenState extends ConsumerState<PhotoStepScreen> {
  int _selectedIndex = 0;
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await ref.read(imagePickerProvider).pickImage(
            source: source,
            imageQuality: 85,
            maxWidth: 2000,
          );
      if (file != null) {
        ref.read(complaintDraftProvider.notifier).addPhoto(file);
        // Preview the newly added photo.
        setState(() {
          _selectedIndex = ref.read(complaintDraftProvider).photos.length - 1;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) _showPermissionDialog(source, e);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Couldn’t open the picker. Try again.')),
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showPermissionDialog(ImageSource source, PlatformException e) {
    final isCamera = source == ImageSource.camera;
    final what = isCamera ? 'camera' : 'photo library';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${isCamera ? 'Camera' : 'Photos'} access needed'),
        content: Text(
          'CivicRoute needs permission to use your $what so you can attach a '
          'photo of the issue.\n\nPlease enable $what access for CivicRoute in '
          'your device Settings, then try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Upload from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pick(source);
  }

  void _removeAt(int index) {
    ref.read(complaintDraftProvider.notifier).removePhotoAt(index);
    final remaining = ref.read(complaintDraftProvider).photos.length;
    setState(() {
      _selectedIndex = _selectedIndex.clamp(0, (remaining - 1).clamp(0, 999));
    });
  }

  Future<void> _retake() async {
    // Drop the previewed photo, then reopen the source chooser to replace it.
    _removeAt(_selectedIndex);
    await _showSourceSheet();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(complaintDraftProvider);
    final photos = draft.photos;
    if (_selectedIndex >= photos.length && photos.isNotEmpty) {
      _selectedIndex = photos.length - 1;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Register Complaint')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: const StepProgressIndicator(
                currentStep: 1,
                totalSteps: 3,
                label: 'Photo',
              ),
            ),
            Expanded(
              child: photos.isEmpty
                  ? _EmptyState(
                      busy: _busy,
                      onTakePhoto: () => _pick(ImageSource.camera),
                      onGallery: () => _pick(ImageSource.gallery),
                    )
                  : _PreviewState(
                      photos: photos,
                      selectedIndex: _selectedIndex,
                      onSelect: (i) => setState(() => _selectedIndex = i),
                      onRemove: _removeAt,
                      onAddAnother: _showSourceSheet,
                      onRetake: _retake,
                    ),
            ),
            _BottomBar(
              enabled: draft.hasPhotos,
              onNext: () => context.push(AppRoutes.complaintDescription),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Empty state ------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.busy,
    required this.onTakePhoto,
    required this.onGallery,
  });

  final bool busy;
  final VoidCallback onTakePhoto;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_a_photo_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Add a photo of the issue',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'A clear photo helps officers understand and locate the problem.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl),
              _SourceOptionCard(
                icon: Icons.camera_alt_outlined,
                label: 'Take Photo',
                description: 'Use your camera',
                onTap: busy ? null : onTakePhoto,
              ),
              const SizedBox(height: AppSpacing.md),
              _SourceOptionCard(
                icon: Icons.photo_library_outlined,
                label: 'Upload from Gallery',
                description: 'Choose an existing photo',
                onTap: busy ? null : onGallery,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceOptionCard extends StatelessWidget {
  const _SourceOptionCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.titleMedium),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Preview state ----------------------------------------------------------

class _PreviewState extends StatelessWidget {
  const _PreviewState({
    required this.photos,
    required this.selectedIndex,
    required this.onSelect,
    required this.onRemove,
    required this.onAddAnother,
    required this.onRetake,
  });

  final List<XFile> photos;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemove;
  final VoidCallback onAddAnother;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadius.lgAll,
                  child: Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    width: double.infinity,
                    child: _PhotoImage(file: photos[selectedIndex]),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onRetake,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retake'),
                ),
              ),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
                  itemBuilder: (context, i) {
                    if (i == photos.length) {
                      return _AddAnotherTile(onTap: onAddAnother);
                    }
                    return _Thumbnail(
                      file: photos[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelect(i),
                      onRemove: () => onRemove(i),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.file,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  final XFile file;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md - 1),
              child: _PhotoImage(file: file),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.surface, width: 2),
                ),
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: theme.colorScheme.onError,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddAnotherTile extends StatelessWidget {
  const _AddAnotherTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: theme.colorScheme.primary),
            Text(
              'Add',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cross-platform image rendering for a picked [XFile].
class _PhotoImage extends StatelessWidget {
  const _PhotoImage({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    Widget errorFallback(BuildContext context, Object _, StackTrace? __) =>
        const Center(child: Icon(Icons.broken_image_outlined));

    if (kIsWeb) {
      return Image.network(file.path, fit: BoxFit.cover, errorBuilder: errorFallback);
    }
    return Image.file(
      File(file.path),
      fit: BoxFit.cover,
      errorBuilder: errorFallback,
    );
  }
}

// --- Bottom bar -------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.enabled, required this.onNext});

  final bool enabled;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: PrimaryButton(
            label: 'Next',
            icon: Icons.arrow_forward,
            onPressed: enabled ? onNext : null,
          ),
        ),
      ),
    );
  }
}
