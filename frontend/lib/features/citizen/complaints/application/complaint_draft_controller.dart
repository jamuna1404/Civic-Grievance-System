import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// In-progress complaint being assembled across the registration stepper.
///
/// Held entirely in memory — photos are NOT uploaded to Supabase Storage until
/// final submit, so a citizen who abandons the flow leaves nothing behind and
/// isn't blocked on a slow upload.
class ComplaintDraft {
  const ComplaintDraft({
    this.photos = const [],
    this.description = '',
    this.usedVoice = false,
    this.lat,
    this.lon,
    this.addressLabel,
    this.departmentId,
  });

  final List<XFile> photos;

  /// Free-text description (typed or voice-transcribed, then editable).
  final String description;

  /// Whether any part of the description was entered by voice — maps to the
  /// complaint's `input_mode` (VOICE vs TEXT).
  final bool usedVoice;

  /// Captured / adjusted location. Null until Step 3 fetches it.
  final double? lat;
  final double? lon;
  final String? addressLabel;

  /// Selected department id (e.g. 'GCC_ELECT'). Null until picked in Step 3.
  final String? departmentId;

  bool get hasPhotos => photos.isNotEmpty;
  bool get hasDescription => description.trim().isNotEmpty;
  bool get hasLocation => lat != null && lon != null;
  bool get hasDepartment => departmentId != null;

  String get inputMode => usedVoice ? 'VOICE' : 'TEXT';

  ComplaintDraft copyWith({
    List<XFile>? photos,
    String? description,
    bool? usedVoice,
    double? lat,
    double? lon,
    String? addressLabel,
    String? departmentId,
  }) =>
      ComplaintDraft(
        photos: photos ?? this.photos,
        description: description ?? this.description,
        usedVoice: usedVoice ?? this.usedVoice,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        addressLabel: addressLabel ?? this.addressLabel,
        departmentId: departmentId ?? this.departmentId,
      );
}

class ComplaintDraftController extends Notifier<ComplaintDraft> {
  @override
  ComplaintDraft build() => const ComplaintDraft();

  void addPhoto(XFile photo) =>
      state = state.copyWith(photos: [...state.photos, photo]);

  void removePhotoAt(int index) {
    if (index < 0 || index >= state.photos.length) return;
    final next = [...state.photos]..removeAt(index);
    state = state.copyWith(photos: next);
  }

  void setDescription(String description) =>
      state = state.copyWith(description: description);

  void markVoiceUsed() => state = state.copyWith(usedVoice: true);

  void setLocation({
    required double lat,
    required double lon,
    String? addressLabel,
  }) =>
      state = state.copyWith(lat: lat, lon: lon, addressLabel: addressLabel);

  void setDepartment(String departmentId) =>
      state = state.copyWith(departmentId: departmentId);

  /// Discards the whole draft (e.g. after a successful submit or cancel).
  void clear() => state = const ComplaintDraft();
}

final complaintDraftProvider =
    NotifierProvider<ComplaintDraftController, ComplaintDraft>(
  ComplaintDraftController.new,
);
