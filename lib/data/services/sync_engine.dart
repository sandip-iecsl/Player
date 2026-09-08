import 'package:flutter/foundation.dart';
import '../../core/sync/adaptive_sync_engine.dart';
import '../models/sync_operation_model.dart';
import '../../core/commands/app_command.dart';
import '../../core/commands/chat_commands.dart';
import '../../core/commands/admin_commands.dart';

@Deprecated('Use AdaptiveSyncEngine directly instead')
class SyncEngine {
  static final SyncEngine _instance = SyncEngine._internal();
  factory SyncEngine() => _instance;
  SyncEngine._internal();

  /// Initialize the Adaptive Sync Engine.
  Future<void> init() async {
    await AdaptiveSyncEngine().initialize();
  }

  /// Compatibility enqueue method for legacy callers.
  /// Translates SyncOperationModel into command instances and schedules them.
  Future<void> enqueue(SyncOperationModel operation) async {
    final String cmdId = operation.id;
    final DateTime timestamp = operation.timestamp;


    AppCommand? command;

    if (operation.collectionPath.startsWith('direct_chats')) {
      final parts = operation.collectionPath.split('/');
      final roomId = parts[1];
      if (operation.action == SyncAction.insert) {
        command = CreateMessageCommand(
          commandId: cmdId,
          timestamp: timestamp,
          payload: {
            'roomId': roomId,
            'messageId': operation.documentId,
            'messageData': operation.data ?? {},
          },
        );
      } else if (operation.action == SyncAction.update) {
        command = UpdateMessageCommand(
          commandId: cmdId,
          timestamp: timestamp,
          payload: {
            'roomId': roomId,
            'messageId': operation.documentId,
            'updateData': operation.data ?? {},
          },
        );
      } else if (operation.action == SyncAction.delete) {
        command = DeleteMessageCommand(
          commandId: cmdId,
          timestamp: timestamp,
          payload: {
            'roomId': roomId,
            'messageId': operation.documentId,
            'updateData': {'deletedForEveryone': true, 'text': 'This message was deleted'},
          },
        );
      }
    } else if (operation.collectionPath == 'live_users') {
      command = UpdatePresenceCommand(
        commandId: cmdId,
        timestamp: timestamp,
        payload: {
          'userId': operation.documentId,
          'presenceData': operation.data ?? {},
        },
      );
    } else if (operation.collectionPath == 'ml_engine_synonyms') {
      command = TrainSearchRuleCommand(
        commandId: cmdId,
        timestamp: timestamp,
        payload: {
          'alias': operation.documentId,
          'mapping': operation.data ?? {},
          'isDelete': operation.action == SyncAction.delete,
        },
      );
    }

    if (command != null) {
      await AdaptiveSyncEngine().enqueue(command);
    } else {
      debugPrint('[LegacySyncEngine] ⚠️ Unmapped sync operation: ${operation.collectionPath}');
    }
  }

  void triggerSync() {
    AdaptiveSyncEngine().forceSync();
  }

  void dispose() {
    // No-op for compatibility
  }
}
