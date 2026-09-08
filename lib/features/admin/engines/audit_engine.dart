import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../data/models/audit_log_model.dart';
import '../../../core/commands/admin_commands.dart';
import '../../../core/sync/adaptive_sync_engine.dart';

class AuditEngine {
  static final AuditEngine _instance = AuditEngine._internal();
  factory AuditEngine() => _instance;
  AuditEngine._internal();

  Box<String>? _auditLogBox;

  Future<void> init() async {
    _auditLogBox = await Hive.openBox<String>('secure_admin_audits');
  }

  /// Write an audit log locally and queue synchronization.
  Future<void> logAction(String actorId, String action, Map<String, dynamic> details) async {
    _auditLogBox ??= await Hive.openBox<String>('secure_admin_audits');

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final log = AuditLogModel(
      logId: id,
      actorId: actorId,
      action: action,
      details: details,
      timestamp: DateTime.now(),
    );

    // Save to local Hive L2 Cache
    await _auditLogBox!.put(id, jsonEncode(log.toJson()));

    // Create and dispatch sync command
    final commandId = 'audit_$id';
    final command = CreateAuditLogCommand(
      commandId: commandId,
      timestamp: DateTime.now(),
      payload: {
        'logId': id,
        'logData': log.toJson(),
      },
    );

    await AdaptiveSyncEngine().enqueue(command);
  }

  /// Fetch local audit logs.
  List<AuditLogModel> getAuditLogs() {
    _auditLogBox ??= Hive.box<String>('secure_admin_audits');

    final List<AuditLogModel> logs = [];
    for (final val in _auditLogBox!.values) {
      try {
        final decoded = jsonDecode(val);
        logs.add(AuditLogModel.fromJson(decoded, decoded['logId'] ?? ''));
      } catch (_) {}
    }
    return logs;
  }
}
