import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/song.dart';

/// x007 Music API Service
/// 
/// Provides search and stream-fetch capabilities across multiple
/// search engines: gaama, seevn, hunjama, mtmusic, wunk.
/// 
/// API base: https://musicapi.x007.workers.dev
class X007MusicService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  static const String _baseUrl = 'https://musicapi.x007.workers.dev';

  /// The available search engines, ordered by reliability
  static const List<String> _searchEngines = [
    'gaama',   // Best for Bollywood/Indian — returns HLS streams
    'seevn',   // Good secondary source — returns direct MP3
    'hunjama', // Broader catalog
    'mtmusic', // Alternate catalog  
    'wunk',    // International catalog
  ];

  /// Search for songs using a specific engine.
  /// Returns a list of raw result maps: {id, title, img}
  Future<List<Map<String, dynamic>>> _searchRaw(
    String query, {
    String engine = 'gaama',
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/search',
        queryParameters: {
          'q': query,
          'searchEngine': engine,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final status = response.data['status'];
        if (status == 200) {
          final List results = response.data['response'] as List? ?? [];
          return results
              .take(limit)
              .map((r) => {
                    'id': r['id']?.toString() ?? '',
                    'title': r['title']?.toString() ?? '',
                    'img': r['img']?.toString() ?? '',
                    'engine': engine,
                  })
              .where((r) => r['id']!.isNotEmpty && r['title']!.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[x007] ⚠️ Search failed on engine "$engine": $e');
    }
    return [];
  }

  /// Fetch the stream URL for a given song ID.
  /// For 'gaama' engine: returns an HLS .m3u8 URL
  /// For other engines: returns a direct .mp3/.mp4 URL
  Future<String?> fetchStreamUrl(String songId) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/fetch',
        queryParameters: {'id': songId},
      );

      if (response.statusCode == 200 && response.data != null) {
        final status = response.data['status'];
        if (status == 200) {
          final url = response.data['response']?.toString();
          if (url != null && url.isNotEmpty && (url.startsWith('http') || url.startsWith('//'))) {
            return url;
          }
        }
      }
    } catch (e) {
      debugPrint('[x007] ⚠️ Fetch stream URL failed for id "$songId": $e');
    }
    return null;
  }

  /// Search across multiple engines in parallel and return Song objects.
  /// This is the primary public API for integration with HybridSearchService.
  Future<List<Song>> searchSongs(
    String query, {
    int limit = 20,
    List<String>? engines,
  }) async {
    final enginesToUse = engines ?? _searchEngines.take(3).toList();
    
    // Fire all engine searches in parallel
    final futures = enginesToUse.map(
      (engine) => _searchRaw(query, engine: engine, limit: limit),
    );
    final allResults = await Future.wait(futures);

    // Merge and deduplicate by normalized title
    final seen = <String>{};
    final mergedRaw = <Map<String, dynamic>>[];
    
    for (final engineResults in allResults) {
      for (final result in engineResults) {
        final normTitle = result['title']!.toString().toLowerCase().trim();
        if (!seen.contains(normTitle)) {
          seen.add(normTitle);
          mergedRaw.add(result);
        }
      }
    }

    // Now resolve stream URLs in parallel (batch of up to `limit` items)
    final batch = mergedRaw.take(limit).toList();
    final streamFutures = batch.map((r) async {
      final streamUrl = await fetchStreamUrl(r['id']!);
      return streamUrl != null
          ? Song(
              id: 'x007_${r['id']}',
              title: r['title'] ?? 'Unknown',
              artist: _extractArtistFromTitle(r['title'] ?? ''),
              albumArt: r['img'],
              album: null,
              duration: Duration.zero, // x007 doesn't return duration
              previewUrl: streamUrl,
            )
          : null;
    });

    final resolved = await Future.wait(streamFutures);
    return resolved.whereType<Song>().toList();
  }

  /// Best-effort artist extraction from a combined title string
  /// e.g. "Jhoome Jo Pathaan" → "Unknown Artist" (can't extract)
  /// e.g. "Song Name - Artist Name" → "Artist Name"
  String _extractArtistFromTitle(String title) {
    // Try common separators
    for (final sep in [' - ', ' | ', ' by ', ' – ']) {
      if (title.contains(sep)) {
        final parts = title.split(sep);
        if (parts.length >= 2) {
          return parts.last.trim();
        }
      }
    }
    return 'Unknown Artist';
  }

  void dispose() {
    _dio.close();
  }
}
