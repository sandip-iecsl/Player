import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/search_models.dart';
import '../providers/audius_search_provider.dart';
import '../providers/deezer_search_provider.dart';
import '../providers/jamendo_search_provider.dart';
import '../providers/jiosaavn_search_provider.dart';
import '../providers/local_search_provider.dart';
import '../providers/mongodb_search_provider.dart';
import '../providers/search_provider.dart';
import '../providers/spotify_search_provider.dart';
import '../providers/youtube_search_provider.dart';
import '../quota/quota_manager.dart';

/// Result packet from multi-provider parallel candidate retrieval
class RetrievalResult {
  final List<SearchCandidate> candidates;
  final Map<SearchProviderType, Duration> latencies;
  final Map<SearchProviderType, int> counts;
  final Map<SearchProviderType, String> errors;

  const RetrievalResult({
    required this.candidates,
    required this.latencies,
    required this.counts,
    required this.errors,
  });
}

/// Candidate Retriever orchestrating parallel, resilient multi-provider queries
class CandidateRetriever {
  final List<SearchProviderClient> _providers;
  final QuotaManager _quotaManager;

  CandidateRetriever({
    List<SearchProviderClient>? providers,
    QuotaManager? quotaManager,
  })  : _providers = providers ?? [
          LocalSearchProvider(),
          JioSaavnSearchProvider(),
          AudiusSearchProvider(),
          JamendoSearchProvider(),
          DeezerSearchProvider(),
          YouTubeSearchProvider(),
          SpotifySearchProvider(),
          MongoDBSearchProvider(),
        ],
        _quotaManager = quotaManager ?? QuotaManager();

  List<SearchProviderClient> get providers => List.unmodifiable(_providers);

  /// Executes parallel multi-provider candidate retrieval
  Future<RetrievalResult> retrieve({
    required ParsedQuery query,
    required SearchRequest request,
  }) async {
    final latencies = <SearchProviderType, Duration>{};
    final counts = <SearchProviderType, int>{};
    final errors = <SearchProviderType, String>{};
    final allCandidates = <SearchCandidate>[];

    // Filter active enabled providers
    final activeProviders = _providers.where((p) {
      if (!p.isEnabled) return false;
      if (!request.enabledProviders.contains(p.provider)) return false;
      if (!_quotaManager.canQuery(p.provider)) {
        debugPrint('[CandidateRetriever] 🚫 Provider ${p.provider.name} exceeded quota. Skipping.');
        errors[p.provider] = 'Quota Exceeded';
        return false;
      }
      return true;
    }).toList();

    // Sort by priority (Local -> JioSaavn -> Audius -> Jamendo -> Deezer -> YouTube -> Spotify -> Mongo)
    activeProviders.sort((a, b) => a.priority.compareTo(b.priority));

    // Execute parallel searches with individual timeouts & error insulation
    final futures = activeProviders.map((client) async {
      final stopwatch = Stopwatch()..start();
      try {
        await _quotaManager.recordRequest(client.provider);
        final results = await client.search(query, request);
        stopwatch.stop();

        latencies[client.provider] = stopwatch.elapsed;
        counts[client.provider] = results.length;
        return results;
      } catch (e) {
        stopwatch.stop();
        latencies[client.provider] = stopwatch.elapsed;
        counts[client.provider] = 0;
        errors[client.provider] = e.toString();
        debugPrint('[CandidateRetriever] ⚠️ Exception from ${client.provider.name}: $e');
        return <SearchCandidate>[];
      }
    });

    final resultsList = await Future.wait(futures);

    for (final list in resultsList) {
      allCandidates.addAll(list);
    }

    return RetrievalResult(
      candidates: allCandidates,
      latencies: latencies,
      counts: counts,
      errors: errors,
    );
  }
}
