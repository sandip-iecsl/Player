import 'dart:async';
import 'package:flutter/foundation.dart';
import 'search_cache_manager.dart';
import 'search_engine_provider.dart';
import 'search_tier.dart';
import 'providers/mongo_atlas_search_provider.dart';
import 'providers/algolia_search_provider.dart';
import 'providers/client_side_fuzzy_search_provider.dart';

/// Automated Failover Search Coordinator (Resilience Chain)
/// 
/// Chains prioritized providers:
/// 1. MongoDB Atlas Search (Tier 1 Primary M0 Cluster)
/// 2. Algolia Search (Tier 2 Free Backup Tier)
/// 3. Client-Side Fuzzy Engine (Tier 3 100% Offline Fail-Safe)
/// 
/// Enforces a strict 3-second timeout per tier and seamless automatic failover
/// upon rate limit (429), quota exceeded, network drop, or server exception.
class FailoverSearchCoordinator {
  final List<ISearchEngineProvider> _providers;
  final SearchCacheManager _cacheManager;
  final Duration _perProviderTimeout;
  final StreamController<SearchMetricEvent> _metricsController =
      StreamController<SearchMetricEvent>.broadcast();

  FailoverSearchCoordinator({
    List<ISearchEngineProvider>? providers,
    SearchCacheManager? cacheManager,
    Duration perProviderTimeout = const Duration(seconds: 3),
  })  : _providers = providers ??
            [
              MongoAtlasSearchProvider(),
              AlgoliaSearchProvider(),
              ClientSideFuzzySearchProvider(),
            ],
        _cacheManager = cacheManager ?? SearchCacheManager(),
        _perProviderTimeout = perProviderTimeout;

  /// Stream of metric events for telemetry and health dashboards
  Stream<SearchMetricEvent> get metricsStream => _metricsController.stream;

  /// Current list of active providers in the failover chain
  List<ISearchEngineProvider> get providers => List.unmodifiable(_providers);

  /// Executes resilient failover search across the provider hierarchy
  Future<SearchResultPayload> executeSearch(
    String query, {
    bool bypassCache = false,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return SearchResultPayload.empty(query: query);
    }

    // ── STEP 1: Local Hive Cache Check (0ms, 0 Cost) ─────────────────────────
    if (!bypassCache) {
      final cachedResult = await _cacheManager.getCachedResults(cleanQuery);
      if (cachedResult != null && cachedResult.isNotEmpty) {
        _logMetric(SearchMetricEvent(
          providerName: cachedResult.providerName,
          tier: SearchTier.cache,
          query: cleanQuery,
          isSuccess: true,
          duration: Duration.zero,
          resultCount: cachedResult.count,
        ));
        return cachedResult;
      }
    }

    // ── STEP 2: Failover Resiliency Chain ────────────────────────────────────
    final totalStopwatch = Stopwatch()..start();
    List<String> failoverReasons = [];

    for (int i = 0; i < _providers.length; i++) {
      final provider = _providers[i];
      final providerStopwatch = Stopwatch()..start();

      debugPrint('[$providerName] 🔄 Attempting Tier ${provider.tier.level}: ${provider.providerName} for "$cleanQuery"');

      try {
        // Wrap execution in strict 3-second timeout limit
        final results = await provider
            .search(cleanQuery)
            .timeout(_perProviderTimeout);

        providerStopwatch.stop();

        if (results.isNotEmpty) {
          debugPrint('[$providerName] ✅ Tier ${provider.tier.level} (${provider.providerName}) succeeded in ${providerStopwatch.elapsedMilliseconds}ms with ${results.length} results');

          // Log success metric
          _logMetric(SearchMetricEvent(
            providerName: provider.providerName,
            tier: provider.tier,
            query: cleanQuery,
            isSuccess: true,
            duration: providerStopwatch.elapsed,
            resultCount: results.length,
          ));

          // Save to local cache in background (Tier 1 & Tier 2 results)
          if (provider.tier.isCloud) {
            unawaited(_cacheManager.cacheResults(cleanQuery, results).catchError((_) {}));
          }

          return SearchResultPayload(
            songs: results,
            tier: provider.tier,
            providerName: provider.providerName,
            latency: providerStopwatch.elapsed,
            isFromCache: false,
            query: cleanQuery,
          );
        } else {
          // Provider returned empty results, proceed to next tier
          const reason = 'Returned 0 results';
          failoverReasons.add('${provider.providerName}: $reason');
          _logMetric(SearchMetricEvent(
            providerName: provider.providerName,
            tier: provider.tier,
            query: cleanQuery,
            isSuccess: false,
            duration: providerStopwatch.elapsed,
            errorMessage: reason,
            resultCount: 0,
          ));
          debugPrint('[$providerName] ⚠️ Tier ${provider.tier.level} returned 0 results. Failing over to next tier...');
        }
      } on TimeoutException catch (e) {
        providerStopwatch.stop();
        final reason = 'Timed out after ${_perProviderTimeout.inSeconds}s';
        failoverReasons.add('${provider.providerName}: $reason');
        _logMetric(SearchMetricEvent(
          providerName: provider.providerName,
          tier: provider.tier,
          query: cleanQuery,
          isSuccess: false,
          duration: providerStopwatch.elapsed,
          errorMessage: 'TimeoutException: $e',
          statusCode: 408,
        ));
        debugPrint('[$providerName] ⏱️ Timeout on ${provider.providerName}. Failing over to next tier...');
      } catch (e) {
        providerStopwatch.stop();
        final reason = e.toString();
        failoverReasons.add('${provider.providerName}: $reason');
        _logMetric(SearchMetricEvent(
          providerName: provider.providerName,
          tier: provider.tier,
          query: cleanQuery,
          isSuccess: false,
          duration: providerStopwatch.elapsed,
          errorMessage: reason,
        ));
        debugPrint('[$providerName] ❌ Failure on ${provider.providerName} ($e). Failing over to next tier...');
      }
    }

    totalStopwatch.stop();
    debugPrint('[$providerName] ⚠️ All providers exhausted for "$cleanQuery" across ${totalStopwatch.elapsedMilliseconds}ms.');

    return SearchResultPayload(
      songs: const [],
      tier: SearchTier.tier3LocalFailsafe,
      providerName: 'Exhausted Chain (Local Fallback)',
      latency: totalStopwatch.elapsed,
      isFromCache: false,
      query: cleanQuery,
    );
  }

  void _logMetric(SearchMetricEvent event) {
    debugPrint(event.toString());
    if (!_metricsController.isClosed) {
      _metricsController.add(event);
    }
  }

  void dispose() {
    _metricsController.close();
  }

  static String get providerName => 'FailoverSearchCoordinator';
}
