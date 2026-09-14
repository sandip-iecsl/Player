/// Base class for all Google Drive and Space relationship exceptions in Aura Player.
abstract class DriveSpaceException implements Exception {
  final String message;
  final dynamic cause;

  const DriveSpaceException(this.message, [this.cause]);

  @override
  String toString() => '$runtimeType: $message${cause != null ? " (Cause: $cause)" : ""}';
}

/// Thrown when Google Sign-In or OAuth authentication is required or expired.
class DriveAuthRequiredException extends DriveSpaceException {
  const DriveAuthRequiredException([super.message = 'Google Drive authentication required or expired.', super.cause]);
}

/// Thrown when Drive API permissions are insufficient or access is denied.
class DrivePermissionDeniedException extends DriveSpaceException {
  const DrivePermissionDeniedException([super.message = 'Google Drive permission denied.', super.cause]);
}

/// Thrown when a targeted Drive folder is deleted, moved, or not found.
class DriveFolderNotFoundException extends DriveSpaceException {
  final String? folderId;
  const DriveFolderNotFoundException(this.folderId, [super.message = 'Google Drive folder was not found.', super.cause]);
}

/// Thrown when a network timeout or connection failure occurs during Drive operations.
class DriveNetworkErrorException extends DriveSpaceException {
  const DriveNetworkErrorException([super.message = 'Network error occurred during Google Drive communication.', super.cause]);
}

/// Thrown when Drive storage quota or rate limits are exceeded.
class DriveQuotaExceededException extends DriveSpaceException {
  const DriveQuotaExceededException([super.message = 'Google Drive storage quota or rate limit exceeded.', super.cause]);
}

/// Thrown when a requested relationship space does not exist in the registry.
class SpaceNotFoundException extends DriveSpaceException {
  final String? spaceId;
  const SpaceNotFoundException(this.spaceId, [super.message = 'Relationship space not found in registry.', super.cause]);
}

/// Thrown when an operation requires an active pairing relationship, but it is archived or inactive.
class PairingNotActiveException extends DriveSpaceException {
  final String? spaceId;
  const PairingNotActiveException([this.spaceId, super.message = 'Pairing relationship is not active.']);
}

/// Thrown when an upload destination is not owned by the current authenticated user.
/// STRICT INVARIANT: Users must never upload into a partner's Drive folder.
class OwnershipViolationException extends DriveSpaceException {
  final String attemptedFolderId;
  final String myFolderId;
  const OwnershipViolationException({
    required this.attemptedFolderId,
    required this.myFolderId,
    String message = 'Security violation: Attempted to upload file to a folder not owned by the current user.',
  }) : super(message);
}
