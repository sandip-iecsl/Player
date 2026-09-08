import '../../data/models/song_model.dart';
import 'search_tier.dart';

/// Standard result envelope returned by search operations
class SearchResultPayload {
  final List<SongModel> songs;
  final SearchTier tier;
  final String providerName;
  final Duration latency;
  final bool isFromCache;
  final String query;

  const SearchResultPayload({
    required this.songs,
    required this.tier,
    required this.providerName,
    required this.latency,
    this.isFromCache = false,
    required this.query,
  });

  bool get isEmpty => songs.isEmpty;
  bool get isNotEmpty => songs.isNotEmpty;
  int get count => songs.length;

  static SearchResultPayload empty({
    required String query,
    SearchTier tier = SearchTier.tier3LocalFailsafe,
    String providerName = 'Local Fail-Safe',
  }) {
    return SearchResultPayload(
      songs: const [],
      tier: tier,
      providerName: providerName,
      latency: Duration.zero,
      isFromCache: false,
      query: query,
    );
  }
}

/// Abstract contract for all Search Engine Providers in the failover architecture
abstract class ISearchEngineProvider {
  /// Name identifier of the search engine provider
  String get providerName;

  /// The resilience tier level of this provider
  SearchTier get tier;

  /// Executes a query against this search provider and returns a list of songs
  Future<List<SongModel>> search(String query);

  /// Performs a fast health check or connectivity test (optional)
  Future<bool> isHealthy() async => true;
}
