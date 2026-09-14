import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import '../../core/shared/error/drive_exceptions.dart';

/// Service managing Google Sign-In authentication and foundational Google Drive API operations.
class DriveService {
  static final DriveService _instance = DriveService._internal();
  factory DriveService() => _instance;
  DriveService._internal();

  @visibleForTesting
  DriveService.forTesting();

  static const List<String> _driveScopes = [
    drive.DriveApi.driveFileScope,
    drive.DriveApi.driveScope,
    'email',
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _driveScopes);

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;

  GoogleSignInAccount? get currentUser => _currentUser;
  drive.DriveApi? get driveApi => _driveApi;
  bool get isAuthenticated => _driveApi != null && _currentUser != null;

  /// Signs in to Google and initializes the [drive.DriveApi] client.
  Future<drive.DriveApi> signIn() async {
    try {
      debugPrint('[DriveService] 🔑 Initiating Google Sign-In...');
      _currentUser = await _googleSignIn.signIn();

      if (_currentUser == null) {
        throw const DriveAuthRequiredException('Google Sign-In was cancelled by the user.');
      }

      final httpClient = await _googleSignIn.authenticatedClient();
      if (httpClient == null) {
        throw const DriveAuthRequiredException('Failed to obtain authenticated HTTP client from Google Sign-In.');
      }

      _driveApi = drive.DriveApi(httpClient);
      debugPrint('[DriveService] ✅ Authenticated as: ${_currentUser!.email}');
      return _driveApi!;
    } catch (e) {
      if (e is DriveSpaceException) rethrow;
      debugPrint('[DriveService] ❌ Sign-in failed: $e');
      throw DriveAuthRequiredException('Google authentication failed: $e', e);
    }
  }

  /// Silently signs in if previous credentials exist.
  Future<drive.DriveApi?> signInSilently() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        final httpClient = await _googleSignIn.authenticatedClient();
        if (httpClient != null) {
          _driveApi = drive.DriveApi(httpClient);
          debugPrint('[DriveService] 🔄 Silent sign-in restored: ${_currentUser!.email}');
          return _driveApi;
        }
      }
    } catch (e) {
      debugPrint('[DriveService] ⚠️ Silent sign-in skipped: $e');
    }
    return null;
  }

  /// Signs out of Google.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;
      _driveApi = null;
      debugPrint('[DriveService] 🚪 Signed out successfully.');
    } catch (e) {
      debugPrint('[DriveService] ⚠️ Sign-out error: $e');
    }
  }

  /// Verifies if a folder exists and is accessible.
  Future<bool> verifyFolderExists(drive.DriveApi api, String folderId) async {
    try {
      final file = await api.files.get(
        folderId,
        $fields: 'id, name, mimeType, trashed',
      ) as drive.File;
      return file.trashed != true && file.mimeType == 'application/vnd.google-apps.folder';
    } catch (e) {
      debugPrint('[DriveService] Folder verification failed for $folderId: $e');
      return false;
    }
  }

  /// Creates a folder in the user's Google Drive.
  Future<drive.File> createFolder(drive.DriveApi api, String folderName) async {
    try {
      final folderMetadata = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final created = await api.files.create(
        folderMetadata,
        $fields: 'id, name, mimeType, createdTime',
      );
      debugPrint('[DriveService] 📁 Folder created: ${created.name} (${created.id})');
      return created;
    } catch (e) {
      debugPrint('[DriveService] ❌ Folder creation failed: $e');
      throw DriveNetworkErrorException('Failed to create Drive folder: $e', e);
    }
  }

  /// Searches for an existing folder by exact name in the user's root Drive.
  Future<drive.File?> findFolderByName(drive.DriveApi api, String folderName) async {
    try {
      final query = "mimeType = 'application/vnd.google-apps.folder' and name = '$folderName' and trashed = false";
      final result = await api.files.list(
        q: query,
        $fields: 'files(id, name, mimeType, createdTime)',
        pageSize: 1,
      );
      if (result.files != null && result.files!.isNotEmpty) {
        return result.files!.first;
      }
      return null;
    } catch (e) {
      debugPrint('[DriveService] ⚠️ findFolderByName error: $e');
      return null;
    }
  }

  /// Lists photos inside a specific Drive folder.
  Future<List<drive.File>> listFilesInFolder(
    drive.DriveApi api,
    String folderId, {
    int pageSize = 100,
  }) async {
    try {
      final query = "'$folderId' in parents and trashed = false and mimeType contains 'image/'";
      final fileList = await api.files.list(
        q: query,
        $fields: 'files(id, name, mimeType, thumbnailLink, webViewLink, webContentLink, createdTime, size, owners)',
        orderBy: 'createdTime desc',
        pageSize: pageSize,
      );
      return fileList.files ?? [];
    } catch (e) {
      debugPrint('[DriveService] ❌ Failed to list files in folder $folderId: $e');
      throw DriveNetworkErrorException('Failed to list files in Drive folder: $e', e);
    }
  }

  /// Uploads a local image file into the specified Drive folder.
  Future<drive.File> uploadFile({
    required drive.DriveApi api,
    required File file,
    required String fileName,
    required String targetFolderId,
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final fileLength = await file.length();
      final mediaStream = file.openRead();
      final media = drive.Media(mediaStream, fileLength);

      final fileMetadata = drive.File()
        ..name = fileName
        ..parents = [targetFolderId]
        ..mimeType = mimeType;

      final uploaded = await api.files.create(
        fileMetadata,
        uploadMedia: media,
        $fields: 'id, name, mimeType, thumbnailLink, webViewLink, webContentLink, createdTime, size',
      );

      debugPrint('[DriveService] 📸 Uploaded $fileName (${uploaded.id}) to folder: $targetFolderId');
      return uploaded;
    } catch (e) {
      debugPrint('[DriveService] ❌ File upload failed: $e');
      throw DriveNetworkErrorException('Failed to upload file to Google Drive: $e', e);
    }
  }

  /// Deletes a file by ID.
  Future<void> deleteFile(drive.DriveApi api, String fileId) async {
    try {
      await api.files.delete(fileId);
      debugPrint('[DriveService] 🗑️ Deleted file $fileId');
    } catch (e) {
      debugPrint('[DriveService] ❌ Failed to delete file $fileId: $e');
      throw DriveNetworkErrorException('Failed to delete file from Google Drive: $e', e);
    }
  }
}
