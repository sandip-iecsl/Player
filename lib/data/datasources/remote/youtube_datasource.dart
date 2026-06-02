import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../domain/entities/song.dart';
import '../../models/song_model.dart';

/// Fetches from **YouTube Data API v3** (music category trending videos)
/// and the **iTunes Search API** (free, no key, real 30s previews).
///
/// YouTube API key is passed at construction time from the app's config.
/// iTunes is used as a fallback/supplement since YouTube tracks won't have
/// direct audio preview URLs (only youtube watch links).
class YoutubeDatasource {
  final Dio _dio;
  final String _apiKey;

  static const String _ytBase = 'https://www.googleapis.com/youtube/v3';
  static const String _itunesBase = 'https://itunes.apple.com/search';

  YoutubeDatasource({required Dio dio, required String apiKey})
      : _dio = dio,
        _apiKey = apiKey;

  // ── YouTube parsers ────────────────────────────────────────────────────────

  SongModel _ytItemToSong(Map<String, dynamic> item) {
    final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
    final videoId = item['id'] as String? ?? '';
    final thumbs = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
    final maxresThumb = (thumbs['maxres'] ?? thumbs['high'] ?? thumbs['medium'])
        as Map<String, dynamic>?;

    return SongModel(
      id: 'yt_$videoId',
      title: snippet['title'] as String? ?? 'Unknown',
      artist: snippet['channelTitle'] as String? ?? 'Unknown Artist',
      albumArt: maxresThumb?['url'] as String?,
      duration: item.containsKey('contentDetails')
          ? _parseDuration(
              (item['contentDetails'] as Map)['duration'] as String? ?? 'PT0S')
          : const Duration(seconds: 210),
      youtubeUrl: 'https://www.youtube.com/watch?v=$videoId',
      // YouTube tracks get their audio through the URL — no direct previewUrl
    );
  }

  Duration _parseDuration(String iso) {
    final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
    final match = regex.firstMatch(iso);
    if (match == null) return const Duration(seconds: 210);
    return Duration(
      hours: int.tryParse(match.group(1) ?? '0') ?? 0,
      minutes: int.tryParse(match.group(2) ?? '0') ?? 0,
      seconds: int.tryParse(match.group(3) ?? '0') ?? 0,
    );
  }

  // ── iTunes parsers ─────────────────────────────────────────────────────────

  SongModel _itunesTrackToSong(Map<String, dynamic> track) {
    final artwork = track['artworkUrl100']
        ?.toString()
        .replaceAll('100x100bb.jpg', '500x500bb.jpg');

    return SongModel(
      id: 'it_${track['trackId'] ?? DateTime.now().millisecondsSinceEpoch}',
      title: track['trackName'] as String? ?? 'Unknown',
      artist: track['artistName'] as String? ?? 'Unknown Artist',
      albumArt: artwork,
      album: track['collectionName'] as String?,
      duration:
          Duration(milliseconds: (track['trackTimeMillis'] as int?) ?? 0),
      deezerUrl: track['trackViewUrl'] as String?,
      // iTunes provides real 30-second MP3 preview URLs — no auth required
      previewUrl: track['previewUrl'] as String?,
    );
  }

  // ── Private fetchers ───────────────────────────────────────────────────────

  /// YouTube most-popular music videos by region.
  Future<List<Song>> _fetchYtTrending({
    String regionCode = 'IN',
    int maxResults = 20,
  }) async {
    if (_apiKey.isEmpty) return [];
    try {
      final response = await _dio.get(
        '$_ytBase/videos',
        queryParameters: {
          'part': 'snippet,contentDetails',
          'chart': 'mostPopular',
          'videoCategoryId': '10', // Music
          'regionCode': regionCode,
          'maxResults': maxResults,
          'key': _apiKey,
        },
      );
      final items = (response.data['items'] as List?) ?? [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(_ytItemToSong)
          .toList();
    } catch (e) {
      print('[YouTube] Trending $regionCode failed: $e');
      return [];
    }
  }

  /// YouTube search for a query term.
  Future<List<Song>> _searchYt(String query, {int maxResults = 15}) async {
    if (_apiKey.isEmpty) return [];
    try {
      // Step 1: search for video IDs
      final searchResp = await _dio.get(
        '$_ytBase/search',
        queryParameters: {
          'part': 'snippet',
          'q': query,
          'type': 'video',
          'videoCategoryId': '10',
          'maxResults': maxResults,
          'key': _apiKey,
        },
      );
      final searchItems = (searchResp.data['items'] as List?) ?? [];
      return searchItems.whereType<Map<String, dynamic>>().map((item) {
        final videoId = (item['id'] as Map?)?['videoId'] as String? ?? '';
        final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
        final thumbs = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
        final highThumb = (thumbs['high'] ?? thumbs['medium']) as Map?;
        return SongModel(
          id: 'yt_$videoId',
          title: snippet['title'] as String? ?? 'Unknown',
          artist: snippet['channelTitle'] as String? ?? 'Unknown Artist',
          albumArt: highThumb?['url'] as String?,
          duration: const Duration(seconds: 210),
          youtubeUrl: 'https://www.youtube.com/watch?v=$videoId',
        );
      }).toList();
    } catch (e) {
      print('[YouTube] Search "$query" failed: $e');
      return [];
    }
  }

  /// iTunes search — always has real 30s preview URLs.
  Future<List<Song>> _searchItunes(String query, {int limit = 20}) async {
    try {
      final response = await _dio.get(
        _itunesBase,
        queryParameters: {'term': query, 'media': 'music', 'limit': limit},
      );
      final data = response.data is String
          ? jsonDecode(response.data)
          : response.data;
      final tracks = (data['results'] as List?) ?? [];
      return tracks
          .whereType<Map<String, dynamic>>()
          .map(_itunesTrackToSong)
          .toList();
    } catch (e) {
      print('[iTunes] Search "$query" failed: $e');
      return [];
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Trending: YouTube India top + iTunes global top — interleaved.
  Future<List<Song>> getTrendingMusic() async {
    final results = await Future.wait([
      _fetchYtTrending(regionCode: 'IN', maxResults: 15),
      _fetchYtTrending(regionCode: 'US', maxResults: 10),
      _searchItunes('top hits 2025', limit: 15),
    ]);
    return _interleave(results).take(30).toList();
  }

  /// Global charts: YouTube US + YouTube GB + iTunes.
  Future<List<Song>> getGlobalCharts() async {
    final results = await Future.wait([
      _fetchYtTrending(regionCode: 'US', maxResults: 15),
      _fetchYtTrending(regionCode: 'GB', maxResults: 10),
      _searchItunes('billboard hot 100 2025', limit: 15),
    ]);
    return _interleave(results).take(30).toList();
  }

  /// New releases: iTunes new releases + YouTube search.
  Future<List<Song>> getNewReleases() async {
    final results = await Future.wait([
      _searchItunes('new music May 2025', limit: 20),
      _searchYt('new music releases 2025', maxResults: 15),
    ]);
    return _interleave(results).take(25).toList();
  }

  /// Today's biggest hits: YouTube most popular + iTunes top 40.
  Future<List<Song>> getTodaysBiggestHits() async {
    final results = await Future.wait([
      _fetchYtTrending(regionCode: 'IN', maxResults: 20),
      _searchItunes('top 40 hits 2025', limit: 20),
    ]);
    return _interleave(results).take(30).toList();
  }

  /// Lo-fi chill — YouTube + iTunes lo-fi tracks.
  Future<List<Song>> getLofiChill() async {
    final results = await Future.wait([
      _searchYt('lofi hip hop chill beats', maxResults: 12),
      _searchItunes('lofi chill study music', limit: 12),
    ]);
    return _interleave(results).take(20).toList();
  }

  /// Deep focus — YouTube + iTunes instrumental/ambient.
  Future<List<Song>> getDeepFocus() async {
    final results = await Future.wait([
      _searchYt('instrumental focus study music', maxResults: 12),
      _searchItunes('piano instrumental ambient focus', limit: 12),
    ]);
    return _interleave(results).take(20).toList();
  }

  /// Late night vibe — YouTube + iTunes smooth R&B / late-night.
  Future<List<Song>> getLateNightVibe() async {
    final results = await Future.wait([
      _searchYt('smooth rnb late night playlist', maxResults: 12),
      _searchItunes('slow jam rnb evening chill', limit: 12),
    ]);
    return _interleave(results).take(20).toList();
  }

  Future<List<Song>> searchSongs(String query) async {
    final results = await Future.wait([
      _searchYt(query, maxResults: 10),
      _searchItunes(query, limit: 10),
    ]);
    return _interleave(results);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<Song> _interleave(List<List<Song>> sources) {
    final result = <Song>[];
    final maxLen = sources.fold(0, (m, s) => s.length > m ? s.length : m);
    for (int i = 0; i < maxLen; i++) {
      for (final source in sources) {
        if (i < source.length) result.add(source[i]);
      }
    }
    return result;
  }

  // ── Discovery-only methods (title + artist pairs for MeloAPI resolution) ──
  //
  // These do NOT return playable songs.
  // They return (title, artist) pairs which MultiSourceAggregator resolves
  // on MeloAPI to get full 320kbps JioSaavn songs.

  /// Returns (title, artist) pairs from YouTube music trending (IN region).
  /// Used as trend discovery signal — audio always comes from MeloAPI.
  Future<List<({String title, String artist})>> getTrendingTitles({
    String regionCode = 'IN',
    int maxResults = 15,
  }) async {
    final songs = await _fetchYtTrending(regionCode: regionCode, maxResults: maxResults);
    return songs.map((s) => (title: s.title, artist: s.artist)).toList();
  }

  /// Returns (title, artist) pairs from a YouTube + iTunes search.
  Future<List<({String title, String artist})>> searchTitles(String query, {int limit = 10}) async {
    final results = await Future.wait([
      _searchYt(query, maxResults: limit ~/ 2),
      _searchItunes(query, limit: limit ~/ 2),
    ]);
    final combined = _interleave(results);
    return combined.map((s) => (title: s.title, artist: s.artist)).toList();
  }

  /// Returns (title, artist) pairs from iTunes top chart.
  Future<List<({String title, String artist})>> getItunesChartTitles({int limit = 15}) async {
    final songs = await _searchItunes('top hits 2025', limit: limit);
    return songs.map((s) => (title: s.title, artist: s.artist)).toList();
  }
}

