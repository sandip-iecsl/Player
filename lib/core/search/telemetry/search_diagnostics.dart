import '../models/search_models.dart';

/// Diagnostics snapshot for developer / admin search inspection
class SearchDiagnostics {
  final String query;
  final ParsedQuery parsedQuery;
  final Duration totalLatency;
  final Map<SearchProviderType, Duration> providerLatencies;
  final Map<SearchProviderType, int> providerCounts;
  final Map<SearchProviderType, String> providerErrors;
  final List<Map<String, dynamic>> topRankedBreakdown;
  final bool isFromCache;
  final bool isOffline;

  const SearchDiagnostics({
    required this.query,
    required this.parsedQuery,
    required this.totalLatency,
    required this.providerLatencies,
    required this.providerCounts,
    required this.providerErrors,
    required this.topRankedBreakdown,
    required this.isFromCache,
    required this.isOffline,
  });

  factory SearchDiagnostics.fromResponse(SearchResponse response) {
    final breakdown = response.rankedResults.take(10).map((r) {
      return {
        'title': r.candidate.title,
        'artist': r.candidate.artist,
        'provider': r.candidate.sourceProvider.name,
        'finalScore': (r.finalScore * 100).toStringAsFixed(1),
        'textRel': (r.features.textRelevance * 100).toStringAsFixed(1),
        'pop': (r.features.popularity * 100).toStringAsFixed(1),
        'taste': (r.features.userAffinity * 100).toStringAsFixed(1),
        'freshness': (r.features.freshness * 100).toStringAsFixed(1),
        'boost': (r.features.exactBoost * 100).toStringAsFixed(1),
        'penalty': (r.features.penalty * 100).toStringAsFixed(1),
      };
    }).toList();

    return SearchDiagnostics(
      query: response.rawQuery,
      parsedQuery: response.parsedQuery,
      totalLatency: response.totalLatency,
      providerLatencies: response.providerLatencies,
      providerCounts: response.providerCandidateCounts,
      providerErrors: response.providerErrors,
      topRankedBreakdown: breakdown,
      isFromCache: response.isFromCache,
      isOffline: response.isOfflineFallback,
    );
  }
}
