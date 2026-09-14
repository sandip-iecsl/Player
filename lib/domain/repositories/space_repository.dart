import '../entities/space.dart';

/// Contract for managing relationship spaces and their Drive folder registries in Firestore.
abstract class SpaceRepository {
  /// Retrieves a specific space document for a given user.
  Future<SpaceEntity?> getSpace({required String uid, required String spaceId});

  /// Retrieves the currently active space for the given user, if one exists.
  Future<SpaceEntity?> getActiveSpace({required String uid});

  /// Saves or updates a space document for a given user.
  Future<void> saveSpace({required String uid, required SpaceEntity space});

  /// Updates the status and timestamps of a space document.
  Future<void> updateSpaceStatus({
    required String uid,
    required String spaceId,
    required SpaceStatus status,
    DateTime? lastPairedAt,
    DateTime? archivedAt,
  });

  /// Updates the partner's Drive folder ID in the current user's space document.
  Future<void> updatePartnerFolderId({
    required String uid,
    required String spaceId,
    required String partnerFolderId,
  });

  /// Lists all space documents (active and archived) for a given user.
  Future<List<SpaceEntity>> listSpaces({required String uid});

  /// Listens to real-time changes of the user's active space.
  Stream<SpaceEntity?> watchActiveSpace({required String uid});
}
