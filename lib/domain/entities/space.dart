/// Lifecycle statuses for relationship spaces.
enum SpaceStatus {
  none,
  pending,
  creatingSpace,
  syncingPermissions,
  active,
  unpairing,
  archived,
  error;

  static SpaceStatus fromString(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return SpaceStatus.pending;
      case 'creating_space':
      case 'creatingspace':
        return SpaceStatus.creatingSpace;
      case 'syncing_permissions':
      case 'syncingpermissions':
        return SpaceStatus.syncingPermissions;
      case 'active':
        return SpaceStatus.active;
      case 'unpairing':
        return SpaceStatus.unpairing;
      case 'archived':
        return SpaceStatus.archived;
      case 'error':
        return SpaceStatus.error;
      default:
        return SpaceStatus.none;
    }
  }

  String get value {
    switch (this) {
      case SpaceStatus.creatingSpace:
        return 'creating_space';
      case SpaceStatus.syncingPermissions:
        return 'syncing_permissions';
      default:
        return name;
    }
  }
}

/// Domain entity representing a paired relationship space and its associated Drive folders.
class SpaceEntity {
  final String spaceId;
  final String partnerUid;
  final String partnerEmail;

  /// The Google Drive folder ID owned by the current user.
  final String myDriveFolderId;

  /// The Google Drive folder ID owned by the partner (read-only access).
  final String? partnerDriveFolderId;

  final SpaceStatus status;
  final DateTime createdAt;
  final DateTime lastPairedAt;
  final DateTime? archivedAt;
  final int schemaVersion;

  const SpaceEntity({
    required this.spaceId,
    required this.partnerUid,
    required this.partnerEmail,
    required this.myDriveFolderId,
    this.partnerDriveFolderId,
    this.status = SpaceStatus.active,
    required this.createdAt,
    required this.lastPairedAt,
    this.archivedAt,
    this.schemaVersion = 1,
  });

  bool get isActive => status == SpaceStatus.active;
  bool get isArchived => status == SpaceStatus.archived;

  SpaceEntity copyWith({
    String? spaceId,
    String? partnerUid,
    String? partnerEmail,
    String? myDriveFolderId,
    String? partnerDriveFolderId,
    SpaceStatus? status,
    DateTime? createdAt,
    DateTime? lastPairedAt,
    DateTime? archivedAt,
    int? schemaVersion,
  }) {
    return SpaceEntity(
      spaceId: spaceId ?? this.spaceId,
      partnerUid: partnerUid ?? this.partnerUid,
      partnerEmail: partnerEmail ?? this.partnerEmail,
      myDriveFolderId: myDriveFolderId ?? this.myDriveFolderId,
      partnerDriveFolderId: partnerDriveFolderId ?? this.partnerDriveFolderId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastPairedAt: lastPairedAt ?? this.lastPairedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpaceEntity &&
          runtimeType == other.runtimeType &&
          spaceId == other.spaceId &&
          partnerUid == other.partnerUid &&
          partnerEmail == other.partnerEmail &&
          myDriveFolderId == other.myDriveFolderId &&
          partnerDriveFolderId == other.partnerDriveFolderId &&
          status == other.status &&
          schemaVersion == other.schemaVersion;

  @override
  int get hashCode =>
      spaceId.hashCode ^
      partnerUid.hashCode ^
      partnerEmail.hashCode ^
      myDriveFolderId.hashCode ^
      partnerDriveFolderId.hashCode ^
      status.hashCode ^
      schemaVersion.hashCode;

  @override
  String toString() {
    return 'SpaceEntity(spaceId: $spaceId, partner: $partnerEmail, myFolder: $myDriveFolderId, partnerFolder: $partnerDriveFolderId, status: ${status.name})';
  }
}
