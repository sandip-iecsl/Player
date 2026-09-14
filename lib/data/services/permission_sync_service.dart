import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../../core/shared/error/drive_exceptions.dart';
import '../../core/shared/utils/space_utils.dart';

/// Service managing idempotent Google Drive permission synchronization for paired relationship folders.
class PermissionSyncService {
  /// Grants read-only (`role: reader`) access to the partner on the specified Drive folder.
  /// Idempotent: checks existing permissions first to prevent duplicate permission entries.
  Future<void> grantPartnerReaderAccess({
    required drive.DriveApi driveApi,
    required String folderId,
    required String partnerEmail,
  }) async {
    final normEmail = SpaceUtils.normalizeEmail(partnerEmail);
    debugPrint('[PERMISSION] 🔍 Checking reader permission for $normEmail on folder: $folderId');

    try {
      // 1. List existing permissions on folder
      final permList = await driveApi.permissions.list(
        folderId,
        $fields: 'permissions(id, role, type, emailAddress)',
      );

      final permissions = permList.permissions ?? [];
      drive.Permission? existingPerm;

      for (final p in permissions) {
        if (p.emailAddress != null &&
            SpaceUtils.normalizeEmail(p.emailAddress!) == normEmail) {
          existingPerm = p;
          break;
        }
      }

      if (existingPerm != null) {
        if (existingPerm.role == 'reader') {
          debugPrint('[PERMISSION] ✅ Reader permission already exists (ID: ${existingPerm.id}). No action needed.');
          return;
        } else {
          // If role is something else, safely update or reset to reader (NEVER allow writer/owner)
          debugPrint('[PERMISSION] ⚠️ Existing permission has non-reader role (${existingPerm.role}). Updating to reader...');
          final updatePerm = drive.Permission()..role = 'reader';
          await driveApi.permissions.update(
            updatePerm,
            folderId,
            existingPerm.id!,
          );
          debugPrint('[PERMISSION] 🔒 Successfully downgraded/updated permission to reader.');
          return;
        }
      }

      // 2. Permission does not exist -> create new reader permission
      debugPrint('[PERMISSION] ➕ Creating reader permission for $normEmail...');
      final newPermission = drive.Permission()
        ..role = 'reader'
        ..type = 'user'
        ..emailAddress = normEmail;

      // Note: sendNotificationEmail = false to prevent spamming partner inbox on pairing
      final created = await driveApi.permissions.create(
        newPermission,
        folderId,
        sendNotificationEmail: false,
        $fields: 'id, role, emailAddress',
      );

      debugPrint('[PERMISSION] 🎉 Successfully granted reader permission (ID: ${created.id}) to $normEmail');
    } catch (e) {
      debugPrint('[PERMISSION] ❌ Failed to grant reader permission on folder $folderId: $e');
      throw DrivePermissionDeniedException('Failed to grant partner read access: $e', e);
    }
  }

  /// Revokes the partner's access to the specified folder during unpair.
  /// Idempotent: safe if permission was already deleted or not found.
  Future<void> revokePartnerReaderAccess({
    required drive.DriveApi driveApi,
    required String folderId,
    required String partnerEmail,
  }) async {
    final normEmail = SpaceUtils.normalizeEmail(partnerEmail);
    debugPrint('[UNPAIR] 🚫 Revoking partner permission for $normEmail on folder: $folderId');

    try {
      final permList = await driveApi.permissions.list(
        folderId,
        $fields: 'permissions(id, role, type, emailAddress)',
      );

      final permissions = permList.permissions ?? [];
      final matchingPerms = permissions.where((p) =>
          p.emailAddress != null &&
          SpaceUtils.normalizeEmail(p.emailAddress!) == normEmail);

      for (final perm in matchingPerms) {
        if (perm.id != null) {
          debugPrint('[UNPAIR] 🗑️ Deleting permission ID: ${perm.id} for $normEmail');
          await driveApi.permissions.delete(folderId, perm.id!);
        }
      }

      debugPrint('[UNPAIR] ✅ Finished revoking permissions for $normEmail.');
    } catch (e) {
      // Graceful error handling: log and continue to allow local unpairing to proceed
      debugPrint('[UNPAIR] ⚠️ Warning while revoking permission (safe fallback): $e');
    }
  }

  /// Verifies if the partner currently holds reader access on the folder.
  Future<bool> verifyReaderAccess({
    required drive.DriveApi driveApi,
    required String folderId,
    required String partnerEmail,
  }) async {
    final normEmail = SpaceUtils.normalizeEmail(partnerEmail);
    try {
      final permList = await driveApi.permissions.list(
        folderId,
        $fields: 'permissions(id, role, type, emailAddress)',
      );
      final permissions = permList.permissions ?? [];
      return permissions.any((p) =>
          p.emailAddress != null &&
          SpaceUtils.normalizeEmail(p.emailAddress!) == normEmail &&
          (p.role == 'reader' || p.role == 'commenter'));
    } catch (e) {
      debugPrint('[PERMISSION] Verification check failed: $e');
      return false;
    }
  }
}
