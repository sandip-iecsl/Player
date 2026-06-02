import 'package:dio/dio.dart';
import '../../core/config/app_config.dart';
import '../../domain/entities/song.dart';
import '../../domain/repositories/music_repository.dart';
import '../datasources/remote/multi_source_aggregator.dart';
import '../services/trending_cache_service.dart';

/// Repository implementation that routes every call through
/// [MultiSourceAggregator] (Melo + Deezer + YouTube + iTunes)
/// with a 6-hour TTL cache in front of each section.
class MusicRepositoryImpl implements MusicRepository {
  final MultiSourceAggregator _aggregator;
  final _cache = TrendingCacheService.instance;

  MusicRepositoryImpl({required Dio dio})
      : _aggregator = MultiSourceAggregator(
          dio: dio,
          youtubeApiKey: AppConfig.youtubeApiKey,
        );

  /// Fetches via [fetcher] or returns cached result if still fresh.
  Future<List<Song>> _cached(
      String key, Future<List<Song>> Function() fetcher) async {
    final cached = _cache.get(key);
    if (cached != null) return cached;
    final result = await fetcher();
    if (result.isNotEmpty) _cache.put(key, result);
    return result;
  }

  // ── Core sections ──────────────────────────────────────────────────────────

  @override
  Future<List<Song>> searchSongs(String query) =>
      // Search is never cached — always real-time
      _aggregator.searchSongs(query);

  @override
  Future<List<Song>> getTrendingMusic() =>
      _cached('trending', _aggregator.getTrendingMusic);

  @override
  Future<List<Song>> getGlobalCharts() =>
      _cached('globalCharts', _aggregator.getGlobalCharts);

  @override
  Future<List<Song>> getNewReleases() =>
      _cached('newReleases', _aggregator.getNewReleases);

  @override
  Future<List<Map<String, dynamic>>> getTopArtists() async => [];

  @override
  Future<List<Song>> getRecommendations() =>
      _cached('recommendations', _aggregator.getRecommendations);

  @override
  Future<List<Song>> getHitsHindi() =>
      _cached('hitsHindi', _aggregator.getHitsHindi);

  // ── Vibe sections ──────────────────────────────────────────────────────────

  @override
  Future<List<Song>> getTodaysBiggestHits() =>
      _cached('todaysBiggestHits', _aggregator.getTodaysBiggestHits);

  @override
  Future<List<Song>> getRecommendedForYou(List<String> genreHints) =>
      _cached('recommendedForYou_${genreHints.join('_')}',
          () => _aggregator.getRecommendedForYou(genreHints));

  @override
  Future<List<Song>> getLofiChillTracks() =>
      _cached('lofiChill', _aggregator.getLofiChillTracks);

  @override
  Future<List<Song>> getDeepFocusTracks() =>
      _cached('deepFocus', _aggregator.getDeepFocusTracks);

  @override
  Future<List<Song>> getLateNightVibeTracks() =>
      _cached('lateNightVibe', _aggregator.getLateNightVibeTracks);
}
