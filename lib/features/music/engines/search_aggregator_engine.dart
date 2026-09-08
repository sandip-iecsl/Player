import '../../../core/kernel/i_engine.dart';

abstract class ISearchProviderAdapter {
  Future<List<UnifiedSearchResult>> search(String query);
}

class UnifiedSearchResult {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String source;
  final double score;

  UnifiedSearchResult({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.source,
    required this.score,
  });
}

class SearchAggregatorEngine implements IEngine {
  static final SearchAggregatorEngine _instance = SearchAggregatorEngine._internal();
  factory SearchAggregatorEngine() => _instance;
  SearchAggregatorEngine._internal();

  final List<ISearchProviderAdapter> _providers = [];

  void registerProvider(ISearchProviderAdapter provider) {
    _providers.add(provider);
  }

  /// Aggregates results from multiple providers with duplicate filtering and weighted ranking.
  Future<List<UnifiedSearchResult>> aggregateSearch(String query) async {
    final List<UnifiedSearchResult> aggregated = [];

    // Run parallel searches
    final futures = _providers.map((p) => p.search(query).catchError((_) => <UnifiedSearchResult>[]));
    final results = await Future.wait(futures);

    for (final list in results) {
      aggregated.addAll(list);
    }

    // Duplicate detection and ranking
    final Map<String, UnifiedSearchResult> uniqueResults = {};
    for (final item in aggregated) {
      final key = '${item.title.toLowerCase().trim()}_${item.artist.toLowerCase().trim()}';
      if (uniqueResults.containsKey(key)) {
        // Keep the one with the higher rank score
        if (item.score > uniqueResults[key]!.score) {
          uniqueResults[key] = item;
        }
      } else {
        uniqueResults[key] = item;
      }
    }

    final sorted = uniqueResults.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return sorted;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    _providers.clear();
  }
}
