import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessageModel {
  final String messageId;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final String? mediaUrl;
  final String? mediaType;
  final bool isStarred;
  final String? replyToId;
  final bool isEdited;
  final bool deletedForEveryone;
  final int version;
  final bool isArchived;

  ChatMessageModel({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.mediaUrl,
    this.mediaType,
    this.isStarred = false,
    this.replyToId,
    this.isEdited = false,
    this.deletedForEveryone = false,
    this.version = 1,
    this.isArchived = false,
  });

  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'senderId': senderId,
    'senderName': senderName,
    'text': text,
    'timestamp': timestamp.toIso8601String(), // Safe for jsonEncode (Hive/Sync Queue)
    'mediaUrl': mediaUrl,
    'mediaType': mediaType,
    'isStarred': isStarred,
    'replyToId': replyToId,
    'isEdited': isEdited,
    'deletedForEveryone': deletedForEveryone,
    'version': version,
    'isArchived': isArchived,
  };

  /// Returns a map formatted specifically for Firestore, converting the
  /// DateTime into a native Firestore Timestamp.
  Map<String, dynamic> toFirestore() {
    final data = toJson();
    data['timestamp'] = Timestamp.fromDate(timestamp);
    return data;
  }

  factory ChatMessageModel.fromJson(Map<String, dynamic> json, String id) {
    final rawTs = json['timestamp'];
    DateTime ts;
    if (rawTs is Timestamp) {
      ts = rawTs.toDate();
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else if (rawTs is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(rawTs);
    } else {
      ts = DateTime.now();
    }

    return ChatMessageModel(
      messageId: id,
      senderId: json['senderId'] ?? '',
      senderName: json['senderName'] ?? '',
      text: json['text'] ?? '',
      timestamp: ts,
      mediaUrl: json['mediaUrl'],
      mediaType: json['mediaType'],
      isStarred: json['isStarred'] ?? false,
      replyToId: json['replyToId'],
      isEdited: json['isEdited'] ?? false,
      deletedForEveryone: json['deletedForEveryone'] ?? false,
      version: json['version'] ?? 1,
      isArchived: json['isArchived'] ?? false,
    );
  }

  ChatMessageModel copyWith({
    String? text,
    bool? isStarred,
    bool? isEdited,
    bool? deletedForEveryone,
    int? version,
    bool? isArchived,
  }) {
    return ChatMessageModel(
      messageId: messageId,
      senderId: senderId,
      senderName: senderName,
      text: text ?? this.text,
      timestamp: timestamp,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      isStarred: isStarred ?? this.isStarred,
      replyToId: replyToId,
      isEdited: isEdited ?? this.isEdited,
      deletedForEveryone: deletedForEveryone ?? this.deletedForEveryone,
      version: version ?? this.version,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}
