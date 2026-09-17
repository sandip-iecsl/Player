import '../models/search_models.dart';
import '../providers/provider_health.dart';

/// Provider Health Monitor aggregating real-time health across all active search providers
class ProviderHealthMonitor {
  static final ProviderHealthMonitor _instance = ProviderHealthMonitor._internal();
  factory ProviderHealthMonitor() => _instance;
  ProviderHealthMonitor._internal();

  final Map<SearchProviderType, ProviderHealth> _monitors = {};

  void register(ProviderHealth health) {
    _monitors[health.provider] = health;
  }

  ProviderHealth? getHealth(SearchProviderType provider) => _monitors[provider];

  Map<SearchProviderType, Map<String, dynamic>> getAllHealthReports() {
    return _monitors.map((key, value) => MapEntry(key, value.toMap()));
  }

  void resetAll() {
    for (final health in _monitors.values) {
      health.reset();
    }
  }
}
