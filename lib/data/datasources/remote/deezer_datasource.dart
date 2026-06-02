import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../domain/entities/song.dart';
import '../../models/song_model.dart';

/// Fetches from the **real Deezer public API** (api.deezer.com).
/// No API key required. Returns tracks with real 30-second audio preview URLs.
class DeezerDatasource {
  final Dio _dio;
  static const String _baseUrl = 'https://api.deezer.com';

  DeezerDatasource({required Dio dio}) : _dio = dio;

  // ── Parser ─────────────────────────────────────────────────────────────────

  SongModel _trackToSong(Map<String, dynamic> track) {
    final albumData = track['album'] as Map<String, dynamic>?;
    final artistData = track['artist'] as Map<String, dynamic>?;

    // Use xl cover (1000×1000) when available, fall back to big (500×500)
    final albumArt = albumData?['cover_xl'] as String? ??
        albumData?['cover_big'] as String? ??
        albumData?['cover_medium'] as String?;

    return SongModel(
      id: 'dz_${track['id']}',
      title: track['title'] as String? ?? 'Unknown',
      artist: artistData?['name'] as String? ?? 'Unknown Artist',
      albumArt: albumArt,
      album: albumData?['title'] as String?,
      duration: Duration(seconds: (track['duration'] as int?) ?? 0),
      deezerUrl: track['link'] as String?,
      // Deezer provides real 30-second MP3 previews — no auth required
      previewUrl: track['preview'] as String?,
    );
  }

  // ── Core private fetchers ──────────────────────────────────────────────────

  Future<List<Song>> _fetchChart(String endpoint, {int limit = 20}) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/$endpoint',
        queryParameters: {'limit': limit},
      );
      final data = response.data is String
          ? jsonDecode(response.data)
          : response.data;
      final tracks = (data['data'] as List?) ?? [];
      return tracks
          .whereType<Map<String, dynamic>>()
          .map(_trackToSong)
          .toList();
    } catch (e) {
      print('[Deezer] $endpoint failed: $e');
      return [];
    }
  }

  Future<List<Song>> _search(String query, {int limit = 20}) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/search',
        queryParameters: {'q': query, 'limit': limit},
      );
      final data = response.data is String
          ? jsonDecode(response.data)
          : response.data;
      final tracks = (data['data'] as List?) ?? [];
      return tracks
          .whereType<Map<String, dynamic>>()
          .map(_trackToSong)
          .toList();
    } catch (e) {
      print('[Deezer] Search "$query" failed: $e');
      return [];
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Global Deezer Top 50 chart
  Future<List<Song>> getGlobalCharts() => _fetchChart('chart/0/tracks');

  /// New releases search
  Future<List<Song>> getNewReleases() => _search('new music 2025');

  /// Trending international pop
  Future<List<Song>> getTrendingMusic() => _fetchChart('chart/0/tracks');

  /// Today's biggest hits (top chart)
  Future<List<Song>> getTodaysBiggestHits() => _fetchChart('chart/0/tracks', limit: 30);

  /// Lo-fi chill tracks
  Future<List<Song>> getLofiChill() => _search('lofi chill relaxing beats', limit: 20);

  /// Deep focus / instrumental
  Future<List<Song>> getDeepFocus() => _search('instrumental ambient piano focus', limit: 20);

  /// Late night smooth / R&B
  Future<List<Song>> getLateNightVibe() => _search('smooth rnb late night slow', limit: 20);

  Future<List<Song>> searchSongs(String query) => _search(query);

  Future<List<Map<String, dynamic>>> getTopArtists() async => [];

  // ── Discovery-only methods (title + artist pairs for MeloAPI resolution) ──

  /// Returns (title, artist) pairs from Deezer's global top chart.
  /// Used by MultiSourceAggregator to discover trending names, not for playback.
  Future<List<({String title, String artist})>> getChartTitles({int limit = 15}) async {
    final songs = await _fetchChart('chart/0/tracks', limit: limit);
    return songs
        .map((s) => (title: s.title, artist: s.artist))
        .toList();
  }

  /// Returns (title, artist) pairs from a Deezer search query.
  Future<List<({String title, String artist})>> searchTitles(String query, {int limit = 10}) async {
    final songs = await _search(query, limit: limit);
    return songs
        .map((s) => (title: s.title, artist: s.artist))
        .toList();
  }
}
