import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../domain/entities/song.dart';
import '../autocomplete/autocomplete_engine.dart';
import '../autocomplete/did_you_mean_engine.dart';
import '../cache/search_cache.dart';
import '../cache/search_cache_key.dart';
import '../dedup/search_deduplicator.dart';
import '../diversity/result_diversifier.dart';
import '../models/search_models.dart';
import '../query/query_intelligence.dart';
import '../ranking/aura_search_ranker.dart';
import 'candidate_merger.dart';
import 'candidate_retriever.dart';

/// Central Search Pipeline coordinating Query Intelligence, Multi-Provider Retrieval,
/// Deduplication, Aura Relevance Ranking, Diversification, and Offline Fallback.
class SearchPipeline {
  final QueryIntelligence _intelligence;
  final SearchCache _cache;
  final CandidateRetriever _retriever;
  final AuraSearchRanker _ranker;
  final ResultDiversifier _diversifier;
  final AutocompleteEngine _autocomplete;

  SearchPipeline({
    QueryIntelligence? intelligence,
    SearchCache? cache,
    CandidateRetriever? retriever,
    AuraSearchRanker? ranker,
    ResultDiversifier? diversifier,
    AutocompleteEngine? autocomplete,
  })  : _intelligence = intelligence ?? QueryIntelligence(),
        _cache = cache ?? SearchCache(),
        _retriever = retriever ?? CandidateRetriever(),
        _ranker = ranker ?? AuraSearchRanker(),
        _diversifier = diversifier ?? const ResultDiversifier(),
        _autocomplete = autocomplete ?? AutocompleteEngine();

  AutocompleteEngine get autocomplete => _autocomplete;
  SearchCache get cache => _cache;
  CandidateRetriever get retriever => _retriever;

  /// Executes full search pipeline
  Future<SearchResponse> execute(SearchRequest request) async {
    final totalStopwatch = Stopwatch()..start();
    final rawQuery = request.query.trim();

    if (rawQuery.isEmpty) {
      return SearchResponse(
        rawQuery: '',
        parsedQuery: _intelligence.parse(''),
        rankedResults: const [],
        songs: const [],
        totalLatency: Duration.zero,
      );
    }

    // 1. Query Intelligence
    final parsedQuery = _intelligence.parse(rawQuery);

    // 2. Search Cache Lookup
    final cacheKey = SearchCacheKey.fromParsedQuery(parsedQuery, region: request.region ?? 'IN');
    final cachedCandidates = _cache.get(cacheKey);

    if (cachedCandidates != null && cachedCandidates.isNotEmpty) {
      debugPrint('[SearchPipeline] ⚡ Returning cached results for "$rawQuery"');
      final ranked = _ranker.rank(candidates: cachedCandidates, query: parsedQuery);
      final diversified = request.enableDiversification
          ? _diversifier.diversify(rankedResults: ranked, query: parsedQuery)
          : ranked;

      final didYouMean = DidYouMeanEngine.evaluate(query: parsedQuery, topResults: diversified);
      final suggestions = _autocomplete.getSuggestions(rawQuery);

      totalStopwatch.stop();
      return SearchResponse(
        rawQuery: rawQuery,
        parsedQuery: parsedQuery,
        rankedResults: diversified,
        songs: diversified.map((r) => r.candidate.toSong()).toList(),
        didYouMean: didYouMean,
        autocompleteSuggestions: suggestions,
        totalLatency: totalStopwatch.elapsed,
        isFromCache: true,
      );
    }

    // 3. Multi-Provider Candidate Retrieval
    final retrieval = await _retriever.retrieve(
      query: parsedQuery,
      request: request,
    );

    // 4. Hard Filtering & Merge
    final filteredCandidates = CandidateMerger.filterAndMerge(
      retrieval.candidates,
      parsedQuery,
    );

    // 5. Deduplication across providers
    final deduplicatedCandidates = request.enableDeduplication
        ? SearchDeduplicator.deduplicate(filteredCandidates)
        : filteredCandidates;

    // 6. Aura Relevance Ranking
    final rankedCandidates = _ranker.rank(
      candidates: deduplicatedCandidates,
      query: parsedQuery,
    );

    // 7. Result Diversification
    final diversifiedResults = request.enableDiversification
        ? _diversifier.diversify(rankedResults: rankedCandidates, query: parsedQuery)
        : rankedCandidates;

    // 8. "Did you mean?" & Autocomplete suggestions
    final didYouMean = DidYouMeanEngine.evaluate(
      query: parsedQuery,
      topResults: diversifiedResults,
    );
    final suggestions = _autocomplete.getSuggestions(rawQuery);

    // 9. Cache valid ranked results
    if (diversifiedResults.isNotEmpty) {
      final candidatesToCache = diversifiedResults.take(30).map((r) => r.candidate).toList();
      _cache.put(cacheKey, candidatesToCache);
    }

    totalStopwatch.stop();

    final isOffline = retrieval.latencies.keys.every((p) => p == SearchProviderType.local) ||
        (retrieval.counts.values.every((c) => c == 0) &&
            retrieval.counts[SearchProviderType.local] != null &&
            retrieval.counts[SearchProviderType.local]! > 0);

    return SearchResponse(
      rawQuery: rawQuery,
      parsedQuery: parsedQuery,
      rankedResults: diversifiedResults,
      songs: diversifiedResults.map((r) => r.candidate.toSong()).toList(),
      didYouMean: didYouMean,
      autocompleteSuggestions: suggestions,
      totalLatency: totalStopwatch.elapsed,
      providerLatencies: retrieval.latencies,
      providerCandidateCounts: retrieval.counts,
      providerErrors: retrieval.errors,
      isFromCache: false,
      isOfflineFallback: isOffline,
    );
  }
}
