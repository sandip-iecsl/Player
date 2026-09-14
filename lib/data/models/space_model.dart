import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/space.dart';

/// Data transfer model for Firestore space documents stored at:
/// `user_profiles/{uid}/spaces/{spaceId}`
class SpaceModel {
  final String spaceId;
  final String partnerUid;
  final String partnerEmail;
  final String myDriveFolderId;
  final String? partnerDriveFolderId;
  final String status;
  final DateTime createdAt;
  final DateTime lastPairedAt;
  final DateTime? archivedAt;
  final int schemaVersion;

  const SpaceModel({
    required this.spaceId,
    required this.partnerUid,
    required this.partnerEmail,
    required this.myDriveFolderId,
    this.partnerDriveFolderId,
    required this.status,
    required this.createdAt,
    required this.lastPairedAt,
    this.archivedAt,
    this.schemaVersion = 1,
  });

  /// Converts this data model to the domain [SpaceEntity].
  SpaceEntity toEntity() {
    return SpaceEntity(
      spaceId: spaceId,
      partnerUid: partnerUid,
      partnerEmail: partnerEmail,
      myDriveFolderId: myDriveFolderId,
      partnerDriveFolderId: partnerDriveFolderId,
      status: SpaceStatus.fromString(status),
      createdAt: createdAt,
      lastPairedAt: lastPairedAt,
      archivedAt: archivedAt,
      schemaVersion: schemaVersion,
    );
  }

  /// Creates a [SpaceModel] from a domain [SpaceEntity].
  factory SpaceModel.fromEntity(SpaceEntity entity) {
    return SpaceModel(
      spaceId: entity.spaceId,
      partnerUid: entity.partnerUid,
      partnerEmail: entity.partnerEmail,
      myDriveFolderId: entity.myDriveFolderId,
      partnerDriveFolderId: entity.partnerDriveFolderId,
      status: entity.status.name,
      createdAt: entity.createdAt,
      lastPairedAt: entity.lastPairedAt,
      archivedAt: entity.archivedAt,
      schemaVersion: entity.schemaVersion,
    );
  }

  /// Serializes the model into a Firestore map representation.
  Map<String, dynamic> toFirestore() {
    return {
      'space_id': spaceId,
      'partner_uid': partnerUid,
      'partner_email': partnerEmail,
      'my_drive_folder_id': myDriveFolderId,
      'partner_drive_folder_id': partnerDriveFolderId,
      'status': status,
      'created_at': Timestamp.fromDate(createdAt),
      'last_paired_at': Timestamp.fromDate(lastPairedAt),
      'archived_at': archivedAt != null ? Timestamp.fromDate(archivedAt!) : null,
      'schema_version': schemaVersion,
    };
  }

  /// Deserializes a Firestore document snapshot.
  factory SpaceModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return SpaceModel.fromMap(data, doc.id);
  }

  /// Deserializes from a raw map.
  factory SpaceModel.fromMap(Map<String, dynamic> data, [String? fallbackId]) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now();
    }

    return SpaceModel(
      spaceId: data['space_id'] as String? ?? fallbackId ?? '',
      partnerUid: data['partner_uid'] as String? ?? '',
      partnerEmail: data['partner_email'] as String? ?? '',
      myDriveFolderId: data['my_drive_folder_id'] as String? ?? '',
      partnerDriveFolderId: data['partner_drive_folder_id'] as String?,
      status: data['status'] as String? ?? SpaceStatus.active.name,
      createdAt: parseDate(data['created_at']),
      lastPairedAt: parseDate(data['last_paired_at']),
      archivedAt: data['archived_at'] != null ? parseDate(data['archived_at']) : null,
      schemaVersion: (data['schema_version'] as num?)?.toInt() ?? 1,
    );
  }

  /// JSON serialization for offline caching / state backups.
  Map<String, dynamic> toJson() {
    return {
      'space_id': spaceId,
      'partner_uid': partnerUid,
      'partner_email': partnerEmail,
      'my_drive_folder_id': myDriveFolderId,
      'partner_drive_folder_id': partnerDriveFolderId,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'last_paired_at': lastPairedAt.toIso8601String(),
      'archived_at': archivedAt?.toIso8601String(),
      'schema_version': schemaVersion,
    };
  }

  factory SpaceModel.fromJson(Map<String, dynamic> json) {
    return SpaceModel.fromMap(json);
  }
}
