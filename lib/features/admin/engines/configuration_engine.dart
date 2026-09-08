import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../core/commands/admin_commands.dart';
import '../../../core/sync/adaptive_sync_engine.dart';
import '../../../core/events/event_dispatcher.dart';
import '../../../core/events/admin_events.dart';
import '../../../core/kernel/configuration_manager.dart';

class ConfigurationEngine {
  static final ConfigurationEngine _instance = ConfigurationEngine._internal();
  factory ConfigurationEngine() => _instance;
  ConfigurationEngine._internal();

  /// Gets current settings from Cloud Firestore.
  Future<Map<String, dynamic>> fetchSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('map_settings')
          .get();

      final data = Map<String, dynamic>.from(doc.data() ?? {});
      final legacyPassword = data['password']?.toString();
      if ((data['adminPasscode'] == null || data['adminPasscode'].toString().isEmpty) &&
          legacyPassword != null && legacyPassword.isNotEmpty) {
        data['adminPasscode'] = legacyPassword;
      }
      return data;
    } catch (_) {
      return {};
    }
  }

  /// Updates app configurations — writes to Firestore immediately AND via command queue.
  Future<void> updateSettings(Map<String, dynamic> settings) async {
    final normalized = Map<String, dynamic>.from(settings);
    final legacyPassword = normalized['password']?.toString();
    if ((normalized['adminPasscode'] == null || normalized['adminPasscode'].toString().isEmpty) &&
        legacyPassword != null && legacyPassword.isNotEmpty) {
      normalized['adminPasscode'] = legacyPassword;
    }

    // 1. Cache locally in SharedPreferences immediately
    await ConfigurationManager().cacheSettings(normalized);

    // 2. Write directly to Firestore right now so other devices get it instantly
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('map_settings')
          .set(normalized, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ConfigEngine] Direct Firestore write failed, falling back to queue: $e');
    }

    // 3. Also enqueue for resilience (handles offline / retry scenarios)
    final commandId = 'settings_${DateTime.now().millisecondsSinceEpoch}';
    final command = UpdateSettingsCommand(
      commandId: commandId,
      timestamp: DateTime.now(),
      payload: {'settings': settings},
    );
    await AdaptiveSyncEngine().enqueue(command);

    // 4. Publish event so in-memory listeners refresh
    EventDispatcher().publish(SettingsUpdatedEvent(
      eventId: commandId,
      timestamp: DateTime.now(),
      settings: settings,
    ));
  }
}
