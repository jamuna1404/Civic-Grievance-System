import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:civicroute/features/citizen/complaints/application/complaint_draft_controller.dart';
import 'package:civicroute/features/citizen/complaints/presentation/photo_step_screen.dart';

/// Fake picker: returns null (user cancelled) on pick, or throws [error] to
/// simulate a denied permission.
class _FakePicker extends ImagePicker {
  _FakePicker({this.error});

  final PlatformException? error;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    if (error != null) throw error!;
    return null;
  }
}

Widget _host(ImagePicker picker) {
  return ProviderScope(
    overrides: [imagePickerProvider.overrideWithValue(picker)],
    child: const MaterialApp(home: PhotoStepScreen()),
  );
}

void main() {
  group('ComplaintDraftController', () {
    test('add / remove / clear photos', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(complaintDraftProvider.notifier);

      expect(container.read(complaintDraftProvider).hasPhotos, isFalse);

      notifier.addPhoto(XFile('a.jpg'));
      notifier.addPhoto(XFile('b.jpg'));
      expect(container.read(complaintDraftProvider).photos.length, 2);

      notifier.removePhotoAt(0);
      final photos = container.read(complaintDraftProvider).photos;
      expect(photos.length, 1);
      expect(photos.single.path, 'b.jpg');

      notifier.removePhotoAt(5); // out of range — no-op
      expect(container.read(complaintDraftProvider).photos.length, 1);

      notifier.clear();
      expect(container.read(complaintDraftProvider).hasPhotos, isFalse);
    });
  });

  testWidgets('empty state offers both sources with Next disabled',
      (tester) async {
    await tester.pumpWidget(_host(_FakePicker()));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Upload from Gallery'), findsOneWidget);

    final nextButton =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
    expect(nextButton.onPressed, isNull); // disabled with no photos
  });

  testWidgets('denied camera permission shows an explanation dialog',
      (tester) async {
    final picker = _FakePicker(
      error: PlatformException(code: 'camera_access_denied'),
    );
    await tester.pumpWidget(_host(picker));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Camera access needed'), findsOneWidget);
  });
}
