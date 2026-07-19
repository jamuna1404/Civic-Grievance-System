import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Uploads complaint photos to storage and returns their public URLs.
abstract class ComplaintStorage {
  Future<List<String>> uploadPhotos(List<XFile> photos);
}

/// Supabase Storage implementation. Photos are uploaded to the
/// [_bucket] bucket under a unique key, and the public URL is returned.
///
/// Assumes a public bucket named `complaint-images` exists. TODO: switch to
/// signed URLs + a private bucket once officer/citizen access rules are in
/// place.
class SupabaseComplaintStorage implements ComplaintStorage {
  SupabaseComplaintStorage(this._client);

  final SupabaseClient _client;
  static const _bucket = 'complaint-images';
  static const _uuid = Uuid();

  @override
  Future<List<String>> uploadPhotos(List<XFile> photos) async {
    final urls = <String>[];
    for (final photo in photos) {
      final ext = p.extension(photo.name).isNotEmpty
          ? p.extension(photo.name)
          : '.jpg';
      final key = '${_uuid.v4()}$ext';
      final bytes = await photo.readAsBytes();

      await _client.storage.from(_bucket).uploadBinary(
            key,
            bytes,
            fileOptions: FileOptions(
              contentType: photo.mimeType ?? 'image/jpeg',
              upsert: false,
            ),
          );
      urls.add(_client.storage.from(_bucket).getPublicUrl(key));
    }
    return urls;
  }
}

final complaintStorageProvider = Provider<ComplaintStorage>(
  (ref) => SupabaseComplaintStorage(Supabase.instance.client),
);
