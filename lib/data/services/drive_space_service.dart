import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../../core/shared/error/drive_exceptions.dart';
import '../../core/shared/utils/space_utils.dart';
import '../../domain/entities/space.dart';
import '../../domain/repositories/space_repository.dart';
import '../repositories/space_repository_impl.dart';
import 'drive_service.dart';

/// Service managing per-user Google Drive folder lifecycle and registry synchronization for relationship spaces.
class DriveSpaceService {
  final SpaceRepository _spaceRepository;
  final DriveService _driveService;

  DriveSpaceService({
    SpaceRepository? spaceRepository,
    DriveService? driveService,
  })  : _spaceRepository = spaceRepository ?? SpaceRepositoryImpl(),
        _driveService = driveService ?? DriveService();

  /// Resolves the current user's Google Drive folder for the deterministic relationship space.
  /// Reuses existing valid folders if already registered, or creates a new dedicated folder in the user's Drive.
  Future<String> getOrCreateMySpaceFolder({
    required String currentUid,
    required String currentUserEmail,
    required String partnerUid,
    required String partnerEmail,
    required drive.DriveApi myDriveApi,
  }) async {
    final normUserEmail = SpaceUtils.normalizeEmail(currentUserEmail);
    final normPartnerEmail = SpaceUtils.normalizeEmail(partnerEmail);
    final spaceId = SpaceUtils.getSharedSpaceId(currentUid, partnerUid);

    debugPrint('[SPACE] 🔍 Resolving relationship space: $spaceId for $normUserEmail & $normPartnerEmail');

    // 1. Primary Registry: Read Space Record from SpaceRepository
    final existingSpace = await _spaceRepository.getSpace(uid: currentUid, spaceId: spaceId);

    if (existingSpace != null && existingSpace.myDriveFolderId.isNotEmpty) {
      final existingFolderId = existingSpace.myDriveFolderId;
      debugPrint('[SPACE] 📋 Found existing registry entry with folder ID: $existingFolderId');

      // 2. Secondary Verification: Verify folder exists on Drive
      final folderExists = await _driveService.verifyFolderExists(myDriveApi, existingFolderId);

      if (folderExists) {
        debugPrint('[SPACE] ✅ Existing folder verified on Drive: $existingFolderId. Reusing space: $spaceId');

        // Reactivate space and update last_paired_at timestamp
        await _spaceRepository.updateSpaceStatus(
          uid: currentUid,
          spaceId: spaceId,
          status: SpaceStatus.active,
          lastPairedAt: DateTime.now(),
        );

        return existingFolderId;
      } else {
        debugPrint('[SPACE] ⚠️ Registered folder ($existingFolderId) was not found on Drive. Controlled recovery initiating...');
      }
    }

    // 3. Fallback: Search Drive for folder with matching name before creating duplicate
    final folderName = SpaceUtils.getSpaceFolderName(spaceId);
    final existingDriveFolder = await _driveService.findFolderByName(myDriveApi, folderName);

    String resolvedFolderId;
    if (existingDriveFolder != null && existingDriveFolder.id != null) {
      resolvedFolderId = existingDriveFolder.id!;
      debugPrint('[SPACE] 🔄 Discovered matching Drive folder by name: $resolvedFolderId');
    } else {
      // 4. Create new folder in CURRENT USER'S Drive
      debugPrint('[SPACE] ➕ Creating new relationship folder in User Drive: $folderName');
      final createdFolder = await _driveService.createFolder(myDriveApi, folderName);
      if (createdFolder.id == null) {
        throw const DriveNetworkErrorException('Created Drive folder returned null ID.');
      }
      resolvedFolderId = createdFolder.id!;
    }

    // 5. Save registry entry in SpaceRepository
    final now = DateTime.now();
    final newSpace = SpaceEntity(
      spaceId: spaceId,
      partnerUid: partnerUid,
      partnerEmail: normPartnerEmail,
      myDriveFolderId: resolvedFolderId,
      partnerDriveFolderId: existingSpace?.partnerDriveFolderId,
      status: SpaceStatus.creatingSpace,
      createdAt: existingSpace?.createdAt ?? now,
      lastPairedAt: now,
      archivedAt: null,
      schemaVersion: 1,
    );

    await _spaceRepository.saveSpace(uid: currentUid, space: newSpace);
    debugPrint('[SPACE] 💾 Saved space registry with folder: $resolvedFolderId');

    return resolvedFolderId;
  }
}
