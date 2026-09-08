import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../kernel/i_engine.dart';
import '../error/error_manager.dart';

class RecoveryManager implements IEngine {
  static final RecoveryManager _instance = RecoveryManager._internal();
  factory RecoveryManager() => _instance;
  RecoveryManager._internal();

  @override
  Future<void> initialize() async {
    debugPrint('[RecoveryManager] 🩹 Initialized.');
  }

  @override
  Future<void> start() async {
    // Run startup check and recovery scan
    await runRecoveryChecks();
  }

  /// Checks local Hive storage states, resolving command locks or cache glitches.
  Future<void> runRecoveryChecks() async {
    debugPrint('[RecoveryManager] 🩹 Checking for local storage recovery requirements...');
    try {
      if (Hive.isBoxOpen('command_sync_queue')) {
        final box = Hive.box<String>('command_sync_queue');
        
        // Scan for commands stuck in "executing" status and reset them to "pending"
        for (final key in box.keys) {
          final val = box.get(key);
          if (val != null) {
            try {
              final json = jsonDecode(val);
              if (json['status'] == 1) { // 1 represents CommandStatus.executing
                json['status'] = 0; // Reset to CommandStatus.pending
                await box.put(key, jsonEncode(json));
                debugPrint('[RecoveryManager] 🩹 Recovered command $key from executing lock.');
              }
            } catch (_) {}
          }
        }
      }
    } catch (e, stack) {
      ErrorManager().captureError(e, stack, context: 'RecoveryManager.runRecoveryChecks');
    }
  }

  /// Triggers local database flush if severe corruption is discovered.
  Future<void> rebuildCacheBoxes() async {
    debugPrint('[RecoveryManager] 🩹 Wiping and rebuilding local cache stores...');
    try {
      await Hive.box<String>('secure_chat_messages').clear();
      debugPrint('[RecoveryManager] 🩹 Local cache directories rebuilt successfully.');
    } catch (e, stack) {
      ErrorManager().captureError(e, stack, context: 'RecoveryManager.rebuildCacheBoxes');
    }
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
