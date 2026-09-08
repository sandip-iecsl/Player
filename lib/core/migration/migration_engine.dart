import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../kernel/i_engine.dart';
import '../shared/error/error_manager.dart';

class MigrationEngine implements IEngine {
  static final MigrationEngine _instance = MigrationEngine._internal();
  factory MigrationEngine() => _instance;
  MigrationEngine._internal();

  static const int latestSchemaVersion = 2; // Current target version
  int _currentSchemaVersion = 1;

  @override
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentSchemaVersion = prefs.getInt('app_schema_version') ?? 1;
      debugPrint('[MigrationEngine] 📂 Current local schema version: $_currentSchemaVersion');
    } catch (e, stack) {
      ErrorManager().captureError(e, stack, context: 'MigrationEngine.initialize');
    }
  }

  @override
  Future<void> start() async {
    if (_currentSchemaVersion < latestSchemaVersion) {
      await runMigrationPipeline();
    }
  }

  /// Run dynamic database and configurations migration pipeline.
  Future<void> runMigrationPipeline() async {
    debugPrint('[MigrationEngine] 📂 Running schema migrations from $_currentSchemaVersion to $latestSchemaVersion...');
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Phase from v1 to v2
      if (_currentSchemaVersion == 1) {
        await _migrateV1ToV2();
        _currentSchemaVersion = 2;
        await prefs.setInt('app_schema_version', 2);
      }

      debugPrint('[MigrationEngine] 📂 Schema migrations complete. Current: $_currentSchemaVersion');
    } catch (e, stack) {
      ErrorManager().captureError(e, stack, context: 'MigrationEngine.runMigrationPipeline');
      await rollbackMigration();
    }
  }

  Future<void> _migrateV1ToV2() async {
    debugPrint('[MigrationEngine] 📂 Upgrading SharedPreferences and Hive schema structures (V1 -> V2)...');
    
    // Simulate updating keys or shifting document paths
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('chat_expiry_hours')) {
      final hours = prefs.getInt('chat_expiry_hours') ?? 24;
      await prefs.setInt('cached_chatExpiryHours', hours);
      await prefs.remove('chat_expiry_hours');
    }
  }

  /// Revert changes if migration pipeline fails.
  Future<void> rollbackMigration() async {
    debugPrint('[MigrationEngine] ⚠️ Rolling back migration changes...');
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentSchemaVersion = 1;
      await prefs.setInt('app_schema_version', 1);
    } catch (e) {
      debugPrint('[MigrationEngine] ❌ Rollback failed: $e');
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
