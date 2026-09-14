/// Domain entity representing a photo stored in Google Drive within a relationship space.
class DrivePhoto {
  final String id;
  final String name;
  final String mimeType;
  final String? thumbnailLink;
  final String? webViewLink;
  final String? webContentLink;
  final DateTime createdTime;
  final int sizeBytes;

  /// UID of the user who owns/uploaded the photo.
  final String ownerUid;

  /// Email of the photo owner.
  final String ownerEmail;

  /// Whether the photo is in the current user's Google Drive.
  final bool isMine;

  /// Google Drive Folder ID where this file is located.
  final String folderId;

  /// Relationship Space ID.
  final String spaceId;

  const DrivePhoto({
    required this.id,
    required this.name,
    required this.mimeType,
    this.thumbnailLink,
    this.webViewLink,
    this.webContentLink,
    required this.createdTime,
    required this.sizeBytes,
    required this.ownerUid,
    required this.ownerEmail,
    required this.isMine,
    required this.folderId,
    required this.spaceId,
  });

  DrivePhoto copyWith({
    String? id,
    String? name,
    String? mimeType,
    String? thumbnailLink,
    String? webViewLink,
    String? webContentLink,
    DateTime? createdTime,
    int? sizeBytes,
    String? ownerUid,
    String? ownerEmail,
    bool? isMine,
    String? folderId,
    String? spaceId,
  }) {
    return DrivePhoto(
      id: id ?? this.id,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      thumbnailLink: thumbnailLink ?? this.thumbnailLink,
      webViewLink: webViewLink ?? this.webViewLink,
      webContentLink: webContentLink ?? this.webContentLink,
      createdTime: createdTime ?? this.createdTime,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      ownerUid: ownerUid ?? this.ownerUid,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      isMine: isMine ?? this.isMine,
      folderId: folderId ?? this.folderId,
      spaceId: spaceId ?? this.spaceId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrivePhoto &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          spaceId == other.spaceId;

  @override
  int get hashCode => id.hashCode ^ spaceId.hashCode;

  @override
  String toString() {
    return 'DrivePhoto(id: $id, name: $name, isMine: $isMine, created: $createdTime, size: $sizeBytes)';
  }
}
