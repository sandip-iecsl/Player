import 'package:cloud_firestore/cloud_firestore.dart';

class AuditLogModel {
  final String logId;
  final String actorId;
  final String action;
  final Map<String, dynamic> details;
  final DateTime timestamp;

  AuditLogModel({
    required this.logId,
    required this.actorId,
    required this.action,
    required this.details,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'logId': logId,
    'actorId': actorId,
    'action': action,
    'details': details,
    'timestamp': Timestamp.fromDate(timestamp),
  };

  factory AuditLogModel.fromJson(Map<String, dynamic> json, String id) => AuditLogModel(
    logId: id,
    actorId: json['actorId'] ?? '',
    action: json['action'] ?? '',
    details: json['details'] != null ? Map<String, dynamic>.from(json['details']) : {},
    timestamp: (json['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );
}
