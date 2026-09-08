import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/commands/admin_commands.dart';
import '../../../core/sync/adaptive_sync_engine.dart';
import '../../../core/events/event_dispatcher.dart';
import '../../../core/events/admin_events.dart';
import '../../../data/services/search_enhancer.dart';

class SearchIntelligenceEngine {
  static final SearchIntelligenceEngine _instance = SearchIntelligenceEngine._internal();
  factory SearchIntelligenceEngine() => _instance;
  SearchIntelligenceEngine._internal();

  final Box _box = Hive.box('ml_training_box');

  /// Train a new alias mapping rule.
  Future<void> trainRule(String alias, String target) async {
    final cleanAlias = alias.trim().toLowerCase();
    final cleanTarget = target.trim().toLowerCase();

    // 1. Update local Hive
    await _box.put(cleanAlias, cleanTarget);

    // 2. Dispatch command to sync to Firestore
    final docId = base64UrlEncode(utf8.encode(cleanAlias));
    final commandId = 'train_${DateTime.now().millisecondsSinceEpoch}_$cleanAlias';
    
    final command = TrainSearchRuleCommand(
      commandId: commandId,
      timestamp: DateTime.now(),
      payload: {
        'alias': cleanAlias,
        'mapping': {
          'alias': cleanAlias,
          'target': cleanTarget,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        'isDelete': false,
      },
    );

    await AdaptiveSyncEngine().enqueue(command);

    // 3. Publish local event
    EventDispatcher().publish(SearchRuleCreatedEvent(
      eventId: commandId,
      timestamp: DateTime.now(),
      synonymId: docId,
      key: cleanAlias,
      value: cleanTarget,
    ));
  }

  /// Delete a trained rule.
  Future<void> deleteRule(String alias) async {
    final cleanAlias = alias.trim().toLowerCase();
    
    // 1. Delete from local Hive
    await _box.delete(cleanAlias);

    // 2. Dispatch command to delete from Firestore
    final docId = base64UrlEncode(utf8.encode(cleanAlias));
    final commandId = 'delete_rule_${DateTime.now().millisecondsSinceEpoch}_$cleanAlias';

    final command = TrainSearchRuleCommand(
      commandId: commandId,
      timestamp: DateTime.now(),
      payload: {
        'alias': cleanAlias,
        'isDelete': true,
      },
    );

    await AdaptiveSyncEngine().enqueue(command);

    // 3. Publish local event
    EventDispatcher().publish(SearchRuleUpdatedEvent(
      eventId: commandId,
      timestamp: DateTime.now(),
      synonymId: docId,
      key: cleanAlias,
      value: '',
    ));
  }

  /// Enhance search query using synonym map.
  String enhanceQuery(String query) {
    return SearchEnhancer.enhanceQuery(query);
  }

  /// Import multiple synonym mappings.
  Future<void> importRules(Map<String, String> rules) async {
    if (rules.isEmpty) return;

    // 1. Put into local Hive
    await _box.putAll(rules);

    // 2. Prepare import rules command payload
    final commandId = 'import_${DateTime.now().millisecondsSinceEpoch}';
    final List<Map<String, dynamic>> rulesPayload = [];

    rules.forEach((alias, target) {
      rulesPayload.add({
        'alias': alias.trim().toLowerCase(),
        'target': target.trim().toLowerCase(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    });

    final command = ImportSearchRulesCommand(
      commandId: commandId,
      timestamp: DateTime.now(),
      payload: {'rules': rulesPayload},
    );

    await AdaptiveSyncEngine().enqueue(command);
  }
}
