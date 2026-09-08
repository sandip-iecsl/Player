enum SyncAction { insert, update, delete, merge }

class SyncOperationModel {
  final String id;
  final String collectionPath;
  final String documentId;
  final SyncAction action;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  SyncOperationModel({
    required this.id,
    required this.collectionPath,
    required this.documentId,
    required this.action,
    this.data,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'collectionPath': collectionPath,
    'documentId': documentId,
    'action': action.name,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };

  factory SyncOperationModel.fromJson(Map<String, dynamic> json) => SyncOperationModel(
    id: json['id'] ?? '',
    collectionPath: json['collectionPath'] ?? '',
    documentId: json['documentId'] ?? '',
    action: SyncAction.values.firstWhere((e) => e.name == json['action']),
    data: json['data'] != null ? Map<String, dynamic>.from(json['data']) : null,
    timestamp: DateTime.parse(json['timestamp']),
  );
}
