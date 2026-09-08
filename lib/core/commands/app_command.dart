import 'package:cloud_firestore/cloud_firestore.dart';

enum CommandPriority { low, medium, high, critical }
enum CommandStatus { pending, executing, completed, failed }

abstract class AppCommand {
  final String commandId;
  final DateTime timestamp;
  int retryCount;
  final CommandPriority priority;
  CommandStatus status;
  final String type;
  final Map<String, dynamic> payload;

  AppCommand({
    required this.commandId,
    required this.timestamp,
    this.retryCount = 0,
    required this.priority,
    this.status = CommandStatus.pending,
    required this.type,
    required this.payload,
  });

  /// Executes the command against the target database or system.
  /// Returns true if successful, false if it failed and needs retry.
  Future<bool> execute();

  static Object? serializeValue(Object? value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), serializeValue(v)));
    } else if (value is List) {
      return value.map(serializeValue).toList();
    } else if (value is FieldValue) {
      final str = value.toString();
      if (str.contains('serverTimestamp')) {
        return {'_type': 'FieldValue', 'value': 'serverTimestamp'};
      }
      return {'_type': 'FieldValue', 'value': 'serverTimestamp'};
    }
    return value;
  }

  static Object? deserializeValue(Object? value) {
    if (value is Map) {
      if (value['_type'] == 'FieldValue' && value['value'] == 'serverTimestamp') {
        return FieldValue.serverTimestamp();
      }
      return value.map((k, v) => MapEntry(k.toString(), deserializeValue(v)));
    } else if (value is List) {
      return value.map(deserializeValue).toList();
    }
    return value;
  }

  Map<String, dynamic> toJson() {
    return {
      'commandId': commandId,
      'timestamp': timestamp.toIso8601String(),
      'retryCount': retryCount,
      'priority': priority.index,
      'status': status.index,
      'type': type,
      'payload': serializeValue(payload) as Map<String, dynamic>,
    };
  }
}
