import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_command.dart';

class UpdateSettingsCommand extends AppCommand {
  UpdateSettingsCommand({
    required String commandId,
    required DateTime timestamp,
    int retryCount = 0,
    CommandPriority priority = CommandPriority.medium,
    CommandStatus status = CommandStatus.pending,
    required Map<String, dynamic> payload,
  }) : super(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          type: 'UpdateSettingsCommand',
          payload: payload,
        );

  @override
  Future<bool> execute() async {
    try {
      final settings = payload['settings'] as Map<String, dynamic>;
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('map_settings')
          .set(settings, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (e) {
      return false;
    }
  }
}

class TrainSearchRuleCommand extends AppCommand {
  TrainSearchRuleCommand({
    required String commandId,
    required DateTime timestamp,
    int retryCount = 0,
    CommandPriority priority = CommandPriority.medium,
    CommandStatus status = CommandStatus.pending,
    required Map<String, dynamic> payload,
  }) : super(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          type: 'TrainSearchRuleCommand',
          payload: payload,
        );

  @override
  Future<bool> execute() async {
    try {
      final alias = payload['alias'] as String;
      final mapping = payload['mapping'] as Map<String, dynamic>;
      final isDelete = payload['isDelete'] as bool? ?? false;

      if (isDelete) {
        await FirebaseFirestore.instance
            .collection('ml_engine_synonyms')
            .doc(alias.toLowerCase())
            .delete()
            .timeout(const Duration(seconds: 8));
      } else {
        await FirebaseFirestore.instance
            .collection('ml_engine_synonyms')
            .doc(alias.toLowerCase())
            .set(mapping)
            .timeout(const Duration(seconds: 8));
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}

class DeleteUserCommand extends AppCommand {
  DeleteUserCommand({
    required String commandId,
    required DateTime timestamp,
    int retryCount = 0,
    CommandPriority priority = CommandPriority.critical,
    CommandStatus status = CommandStatus.pending,
    required Map<String, dynamic> payload,
  }) : super(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          type: 'DeleteUserCommand',
          payload: payload,
        );

  @override
  Future<bool> execute() async {
    try {
      final userId = payload['userId'] as String;
      final defaultFirestore = FirebaseFirestore.instance;
      final chatFirestore = FirebaseFirestore.instance;
      final failures = <String>[];

      Future<void> runStep(String label, Future<void> Function() action) async {
        try {
          await action();
        } catch (e) {
          failures.add('$label: $e');
        }
      }

      await runStep('users', () async => defaultFirestore.collection('users').doc(userId).delete().timeout(const Duration(seconds: 8)));
      await runStep('pending_deliveries', () async {
        final queues = await defaultFirestore.collection('pending_deliveries').doc(userId).collection('queues').get().timeout(const Duration(seconds: 8));
        if (queues.docs.isEmpty) {
          return;
        }
        final batch = defaultFirestore.batch();
        for (final doc in queues.docs) {
          batch.delete(doc.reference);
        }
        batch.delete(defaultFirestore.collection('pending_deliveries').doc(userId));
        await batch.commit().timeout(const Duration(seconds: 8));
      });
      await runStep('live_users', () async => chatFirestore.collection('live_users').doc(userId).delete().timeout(const Duration(seconds: 8)));
      await runStep('presence_cleanup', () async {
        await chatFirestore.collection('live_users').doc(userId).set({'status': 'offline', 'lastActive': FieldValue.serverTimestamp()}, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
      });

      if (failures.isNotEmpty) {
        print('[DeleteUserCommand] Cleanup completed with failures: $failures');
      }

      return true;
    } catch (e) {
      print('[DeleteUserCommand] Fatal cleanup error: $e');
      return false;
    }
  }
}

class ExportUsersCommand extends AppCommand {
  ExportUsersCommand({
    required String commandId,
    required DateTime timestamp,
    int retryCount = 0,
    CommandPriority priority = CommandPriority.low,
    CommandStatus status = CommandStatus.pending,
    required Map<String, dynamic> payload,
  }) : super(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          type: 'ExportUsersCommand',
          payload: payload,
        );

  @override
  Future<bool> execute() async {
    // Simulated CSV export action for logging or debugging
    return true;
  }
}

class ImportSearchRulesCommand extends AppCommand {
  ImportSearchRulesCommand({
    required String commandId,
    required DateTime timestamp,
    int retryCount = 0,
    CommandPriority priority = CommandPriority.medium,
    CommandStatus status = CommandStatus.pending,
    required Map<String, dynamic> payload,
  }) : super(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          type: 'ImportSearchRulesCommand',
          payload: payload,
        );

  @override
  Future<bool> execute() async {
    try {
      final rules = payload['rules'] as List<dynamic>;
      final batch = FirebaseFirestore.instance.batch();

      for (final rule in rules) {
        final r = rule as Map<String, dynamic>;
        final alias = r['alias'] as String;
        final docRef = FirebaseFirestore.instance
            .collection('ml_engine_synonyms')
            .doc(alias.toLowerCase());
        batch.set(docRef, r);
      }

      await batch.commit().timeout(const Duration(seconds: 8));
      return true;
    } catch (e) {
      return false;
    }
  }
}

class CreateAuditLogCommand extends AppCommand {
  CreateAuditLogCommand({
    required String commandId,
    required DateTime timestamp,
    int retryCount = 0,
    CommandPriority priority = CommandPriority.low,
    CommandStatus status = CommandStatus.pending,
    required Map<String, dynamic> payload,
  }) : super(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          type: 'CreateAuditLogCommand',
          payload: payload,
        );

  @override
  Future<bool> execute() async {
    try {
      final logId = payload['logId'] as String;
      final logData = payload['logData'] as Map<String, dynamic>;

      // Covert string timestamp back to Timestamp for Firestore
      if (logData['timestamp'] is String) {
        logData['timestamp'] = Timestamp.fromDate(DateTime.parse(logData['timestamp'] as String));
      }

      await FirebaseFirestore.instance
          .collection('audit_logs')
          .doc(logId)
          .set(logData)
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (e) {
      return false;
    }
  }
}

