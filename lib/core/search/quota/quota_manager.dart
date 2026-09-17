import '../models/search_models.dart';
import 'provider_quota.dart';
import 'quota_store.dart';

/// Quota Manager managing client-side and backend-coordinated rate limits
class QuotaManager {
  static final QuotaManager _instance = QuotaManager._internal();
  factory QuotaManager() => _instance;
  QuotaManager._internal();

  final QuotaStore _store = QuotaStore();
  final Map<SearchProviderType, ProviderQuota> _quotas = {};
  bool _isInitialized = false;

  // Default daily limits
  static const Map<SearchProviderType, int> _defaultLimits = {
    SearchProviderType.local: 1000000,
    SearchProviderType.audius: 10000,
    SearchProviderType.jamendo: 10000,
    SearchProviderType.jiosaavn: 15000,
    SearchProviderType.deezer: 5000,
    SearchProviderType.youtube: 10000, // YouTube Data API 10k quota units/day
    SearchProviderType.spotify: 10000,
    SearchProviderType.mongodb: 50000,
  };

  void init() {
    if (_isInitialized) return;
    for (final entry in _defaultLimits.entries) {
      final cost = entry.key == SearchProviderType.youtube ? 100 : 1; // YouTube search.list costs 100 units
      _quotas[entry.key] = _store.loadQuota(entry.key, entry.value, cost: cost)!;
    }
    _isInitialized = true;
  }

  bool canQuery(SearchProviderType provider) {
    if (!_isInitialized) init();
    final quota = _quotas[provider];
    if (quota == null) return true;
    return quota.canMakeRequest();
  }

  Future<void> recordRequest(SearchProviderType provider) async {
    if (!_isInitialized) init();
    final quota = _quotas[provider];
    if (quota != null) {
      quota.recordRequest();
      await _store.saveQuota(quota);
    }
  }

  Map<SearchProviderType, ProviderQuota> get allQuotas {
    if (!_isInitialized) init();
    return Map.unmodifiable(_quotas);
  }
}
