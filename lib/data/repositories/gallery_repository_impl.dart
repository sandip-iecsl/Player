import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../../core/shared/error/drive_exceptions.dart';
import '../../domain/entities/drive_photo.dart';
import '../../domain/repositories/gallery_repository.dart';
import '../../domain/repositories/space_repository.dart';
import '../services/drive_service.dart';

/// Implementation of [GalleryRepository] enforcing dual-drive parallel querying,
/// per-user Drive upload ownership, and robust cache invalidation.
class GalleryRepositoryImpl implements GalleryRepository {
  final SpaceRepository _spaceRepository;
  final DriveService _driveService;

  List<DrivePhoto>? _cachedPhotos;
  String? _cachedSpaceId;

  GalleryRepositoryImpl({
    required SpaceRepository spaceRepository,
    DriveService? driveService,
  })  : _spaceRepository = spaceRepository,
        _driveService = driveService ?? DriveService();

  @override
  void invalidateCache() {
    debugPrint('[GALLERY] 🧹 Invaliding gallery cache.');
    _cachedPhotos = null;
    _cachedSpaceId = null;
  }

  @override
  Future<List<DrivePhoto>> getActiveGalleryPhotos({
    required String currentUid,
    required drive.DriveApi driveApi,
    bool forceRefresh = false,
  }) async {
    // 1. Resolve active space
    final activeSpace = await _spaceRepository.getActiveSpace(uid: currentUid);

    if (activeSpace == null) {
      debugPrint('[GALLERY] ℹ️ No active space found. Querying solo/unpaired gallery.');
      return [];
    }

    if (!forceRefresh && _cachedPhotos != null && _cachedSpaceId == activeSpace.spaceId) {
      debugPrint('[GALLERY] ⚡ Returning ${_cachedPhotos!.length} cached photos for space: ${activeSpace.spaceId}');
      return _cachedPhotos!;
    }

    final myFolderId = activeSpace.myDriveFolderId;
    final partnerFolderId = activeSpace.partnerDriveFolderId;
    final isPaired = activeSpace.isActive && partnerFolderId != null && partnerFolderId.isNotEmpty;

    debugPrint('[GALLERY] 📸 Fetching photos (isPaired: $isPaired, myFolder: $myFolderId, partnerFolder: $partnerFolderId)');

    // 2. Query own folder
    final Future<List<drive.File>> myPhotosFuture = myFolderId.isNotEmpty
        ? _driveService.listFilesInFolder(driveApi, myFolderId)
        : Future.value([]);

    // 3. Query partner folder ONLY if actively paired
    final Future<List<drive.File>> partnerPhotosFuture = isPaired
        ? _driveService.listFilesInFolder(driveApi, partnerFolderId).catchError((e) {
            debugPrint('[GALLERY] ⚠️ Error querying partner folder ($partnerFolderId): $e');
            return <drive.File>[];
          })
        : Future.value(<drive.File>[]);

    // 4. Parallel execution
    final results = await Future.wait([myPhotosFuture, partnerPhotosFuture]);
    final myDriveFiles = results[0];
    final partnerDriveFiles = results[1];

    debugPrint('[GALLERY] 📊 Retrieved ${myDriveFiles.length} own photos, ${partnerDriveFiles.length} partner photos');

    final List<DrivePhoto> allPhotos = [];

    // Map own photos
    for (final file in myDriveFiles) {
      if (file.id != null) {
        allPhotos.add(DrivePhoto(
          id: file.id!,
          name: file.name ?? 'Photo',
          mimeType: file.mimeType ?? 'image/jpeg',
          thumbnailLink: file.thumbnailLink,
          webViewLink: file.webViewLink,
          webContentLink: file.webContentLink,
          createdTime: file.createdTime ?? DateTime.now(),
          sizeBytes: int.tryParse(file.size ?? '0') ?? 0,
          ownerUid: currentUid,
          ownerEmail: _driveService.currentUser?.email ?? '',
          isMine: true,
          folderId: myFolderId,
          spaceId: activeSpace.spaceId,
        ));
      }
    }

    // Map partner photos
    for (final file in partnerDriveFiles) {
      if (file.id != null) {
        allPhotos.add(DrivePhoto(
          id: file.id!,
          name: file.name ?? 'Photo',
          mimeType: file.mimeType ?? 'image/jpeg',
          thumbnailLink: file.thumbnailLink,
          webViewLink: file.webViewLink,
          webContentLink: file.webContentLink,
          createdTime: file.createdTime ?? DateTime.now(),
          sizeBytes: int.tryParse(file.size ?? '0') ?? 0,
          ownerUid: activeSpace.partnerUid,
          ownerEmail: activeSpace.partnerEmail,
          isMine: false,
          folderId: partnerFolderId!,
          spaceId: activeSpace.spaceId,
        ));
      }
    }

    // 5. Deduplicate and sort by creation time (descending)
    final Map<String, DrivePhoto> uniqueMap = {};
    for (final photo in allPhotos) {
      uniqueMap[photo.id] = photo;
    }

    final sortedList = uniqueMap.values.toList()
      ..sort((a, b) => b.createdTime.compareTo(a.createdTime));

    _cachedPhotos = sortedList;
    _cachedSpaceId = activeSpace.spaceId;

    return sortedList;
  }

  @override
  Future<DrivePhoto> uploadPhoto({
    required String currentUid,
    required String filePath,
    required String fileName,
    required drive.DriveApi driveApi,
  }) async {
    // 1. Resolve active space
    final activeSpace = await _spaceRepository.getActiveSpace(uid: currentUid);
    if (activeSpace == null) {
      throw const PairingNotActiveException(null, 'Cannot upload photo: No active relationship space found.');
    }

    final myFolderId = activeSpace.myDriveFolderId;
    final partnerFolderId = activeSpace.partnerDriveFolderId;

    if (myFolderId.isEmpty) {
      throw DriveFolderNotFoundException(myFolderId, 'User relationship folder is missing from space registry.');
    }

    // 2. STRICT OWNERSHIP GUARANTEE: Defensive check
    if (partnerFolderId != null && myFolderId == partnerFolderId) {
      throw OwnershipViolationException(
        attemptedFolderId: myFolderId,
        myFolderId: myFolderId,
        message: 'Folder ID conflict: Target folder matches partner folder ID.',
      );
    }

    final currentUserEmail = _driveService.currentUser?.email ?? '';
    debugPrint('[UPLOAD] 🚀 Uploading photo to MY folder:');
    debugPrint('[UPLOAD]   -> uploaderUid: $currentUid');
    debugPrint('[UPLOAD]   -> uploaderEmail: $currentUserEmail');
    debugPrint('[UPLOAD]   -> targetFolderId: $myFolderId (my_drive_folder_id)');
    debugPrint('[UPLOAD]   -> spaceId: ${activeSpace.spaceId}');

    // 3. Perform upload to MY Drive only
    final file = File(filePath);
    if (!await file.exists()) {
      throw DriveNetworkErrorException('Source photo file does not exist at path: $filePath');
    }

    final uploadedFile = await _driveService.uploadFile(
      api: driveApi,
      file: file,
      fileName: fileName,
      targetFolderId: myFolderId,
    );

    final newPhoto = DrivePhoto(
      id: uploadedFile.id!,
      name: uploadedFile.name ?? fileName,
      mimeType: uploadedFile.mimeType ?? 'image/jpeg',
      thumbnailLink: uploadedFile.thumbnailLink,
      webViewLink: uploadedFile.webViewLink,
      webContentLink: uploadedFile.webContentLink,
      createdTime: uploadedFile.createdTime ?? DateTime.now(),
      sizeBytes: int.tryParse(uploadedFile.size ?? '0') ?? 0,
      ownerUid: currentUid,
      ownerEmail: currentUserEmail,
      isMine: true,
      folderId: myFolderId,
      spaceId: activeSpace.spaceId,
    );

    // Update in-memory cache
    if (_cachedPhotos != null) {
      _cachedPhotos!.insert(0, newPhoto);
    }

    return newPhoto;
  }

  @override
  Future<void> deleteMyPhoto({
    required String currentUid,
    required String fileId,
    required drive.DriveApi driveApi,
  }) async {
    // Find photo in cache to verify ownership
    if (_cachedPhotos != null) {
      final photo = _cachedPhotos!.firstWhere(
        (p) => p.id == fileId,
        orElse: () => throw DriveFolderNotFoundException(fileId, 'Photo not found in active gallery.'),
      );

      if (!photo.isMine) {
        throw OwnershipViolationException(
          attemptedFolderId: photo.folderId,
          myFolderId: '',
          message: 'Cannot delete photos owned by partner.',
        );
      }
    }

    await _driveService.deleteFile(driveApi, fileId);

    if (_cachedPhotos != null) {
      _cachedPhotos!.removeWhere((p) => p.id == fileId);
    }
  }
}
