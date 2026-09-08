import 'package:flutter/widgets.dart';
import '../kernel/i_engine.dart';

class ConfigurationRegistry implements IEngine {
  static final ConfigurationRegistry _instance = ConfigurationRegistry._internal();
  factory ConfigurationRegistry() => _instance;
  ConfigurationRegistry._internal();

  final Map<String, Map<String, dynamic>> _namespaces = {
    'security': {
      // lock_code intentionally omitted — always read from Firestore via SecurityEngine
      'auth_timeout_sec': 30,
    },
    'playback': {
      'equalizer_enabled': true,
      'crossfade_ms': 500,
    },
    'chat': {
      'max_unread_count': 99,
      'archive_expiry_hours': 24,
    },
  };

  @override
  Future<void> initialize() async {
    debugPrint('[ConfigurationRegistry] ⚙️ Configuration registry namespace maps initialized.');
  }

  @override
  Future<void> start() async {}

  /// Fetch setting details by namespace key.
  T getSetting<T>(String namespace, String key, T defaultValue) {
    final map = _namespaces[namespace];
    if (map != null && map.containsKey(key)) {
      return map[key] as T;
    }
    return defaultValue;
  }

  /// Update setting configurations.
  void updateSetting(String namespace, String key, dynamic value) {
    if (!_namespaces.containsKey(namespace)) {
      _namespaces[namespace] = {};
    }
    _namespaces[namespace]![key] = value;
    debugPrint('[ConfigurationRegistry] ⚙️ Updated $namespace.$key = $value');
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    _namespaces.clear();
  }
}
