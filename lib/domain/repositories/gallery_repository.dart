import 'package:googleapis/drive/v3.dart' as drive;
import '../entities/drive_photo.dart';

/// Contract for managing relationship gallery photos across dual Google Drive folders.
abstract class GalleryRepository {
  /// Fetches photos from the active gallery.
  /// If paired: queries both own Drive folder and partner's Drive folder in parallel,
  /// merging, deduplicating, and ordering by created date.
  /// If unpaired: queries own Drive folder only.
  Future<List<DrivePhoto>> getActiveGalleryPhotos({
    required String currentUid,
    required drive.DriveApi driveApi,
    bool forceRefresh = false,
  });

  /// Uploads a photo to the user's Google Drive relationship space folder.
  ///
  /// STRICT INVARIANT: Target destination must ALWAYS be `my_drive_folder_id`.
  /// Never uploads directly to the partner's Drive folder.
  Future<DrivePhoto> uploadPhoto({
    required String currentUid,
    required String filePath,
    required String fileName,
    required drive.DriveApi driveApi,
  });

  /// Deletes a photo from the user's own Drive folder.
  /// (Cannot delete photos owned by the partner).
  Future<void> deleteMyPhoto({
    required String currentUid,
    required String fileId,
    required drive.DriveApi driveApi,
  });

  /// Clears in-memory gallery cache.
  void invalidateCache();
}
