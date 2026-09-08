import 'package:hive_flutter/hive_flutter.dart';
import '../../data/models/ml_synonym_model.dart';
import '../../features/admin/engines/audit_engine.dart';
import '../../features/admin/engines/search_intelligence_engine.dart';

import '../../core/kernel/i_engine.dart';

class AdminRepository implements IEngine {
  static final AdminRepository _instance = AdminRepository._internal();
  factory AdminRepository() => _instance;
  AdminRepository._internal();

  Future<void> init() async {
    await AuditEngine().init();
  }

  /// Log admin action.
  Future<void> logAction(String actorId, String action, Map<String, dynamic> details) async {
    await AuditEngine().logAction(actorId, action, details);
  }

  /// Train a new search synonym rule.
  Future<void> saveMLRule(MLSynonymModel rule) async {
    await SearchIntelligenceEngine().trainRule(rule.alias, rule.target);
  }

  /// Deletes a trained synonym rule.
  Future<void> deleteMLRule(String alias) async {
    await SearchIntelligenceEngine().deleteRule(alias);
  }

  /// Get cached ML rules.
  List<MLSynonymModel> getMLRules() {
    final Box mlRulesBox = Hive.box('ml_training_box');
    final List<MLSynonymModel> rules = [];
    
    for (final key in mlRulesBox.keys) {
      if (key.toString().startsWith('_')) continue; // Skip settings/meta keys
      final val = mlRulesBox.get(key);
      rules.add(MLSynonymModel(
        alias: key.toString(),
        target: val.toString(),
        category: 'general',
        weight: 1.0,
        frequency: 1,
        updatedAt: DateTime.now(),
        version: 1,
      ));
    }
    return rules;
  }

  @override
  Future<void> initialize() async {
    await init();
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
