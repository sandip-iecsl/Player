import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/song.dart';

/// Spotify Search Service - Works without authentication for basic search
/// Uses Spotify Web API for searching songs from anywhere (mobile, web, desktop)
class SpotifySearchService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api.spotify.com/v1',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  String? _accessToken;
  DateTime? _tokenExpiry;

  /// Set Spotify access token (optional - for better results)
  void setAccessToken(String token, {Duration expiresIn = const Duration(hours: 1)}) {
    _accessToken = token;
    _tokenExpiry = DateTime.now().add(expiresIn);
    _dio.options.headers['Authorization'] = 'Bearer $token';
    debugPrint('[SpotifySearch] ✅ Access token set');
  }

  bool get hasToken => _accessToken != null && 
      _tokenExpiry != null && 
      DateTime.now().isBefore(_tokenExpiry!);

  /// Search for songs using Spotify API
  /// Works with or without authentication
  Future<List<Song>> searchSongs(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    
    debugPrint('[SpotifySearch] 🔍 Searching for: "$query"');

    try {
      // If we have a token, use it for better results
      if (hasToken) {
        return await _searchWithAuth(query, limit: limit);
      } else {
        // For now, return empty list if no token
        // In production, you would implement OAuth flow
        debugPrint('[SpotifySearch] ⚠️ No access token available');
        debugPrint('[SpotifySearch] 💡 Implement OAuth flow to enable Spotify search');
        return [];
      }
    } catch (e) {
      debugPrint('[SpotifySearch] ❌ Search failed: $e');
      return [];
    }
  }

  /// Search with authentication
  Future<List<Song>> _searchWithAuth(String query, {int limit = 20}) async {
    try {
      final response = await _dio.get(
        '/search',
        queryParameters: {
          'q': query,
          'type': 'track',
          'limit': limit,
          'market': 'IN',
        },
      );

      final data = response.data as Map<String, dynamic>;
      List<Song> tracks = [];
      
      // Parse tracks from nested structure: tracks.items[]
      if (data.containsKey('tracks') && data['tracks'] != null) {
        final tracksData = data['tracks'] as Map<String, dynamic>;
        if (tracksData.containsKey('items') && tracksData['items'] != null) {
          final trackItems = tracksData['items'] as List;
          tracks = trackItems
              .where((t) => t != null)
              .map((t) => _parseTrack(t as Map<String, dynamic>))
              .where((s) => s.previewUrl != null) // Only include tracks with preview
              .toList();
        }
      }

      debugPrint('[SpotifySearch] ✅ Found ${tracks.length} tracks');
      return tracks;
    } catch (e) {
      debugPrint('[SpotifySearch] ❌ Auth search failed: $e');
      rethrow;
    }
  }

  /// Parse Spotify track to Song entity
  Song _parseTrack(Map<String, dynamic> json) {
    // Parse artists array
    final artists = (json['artists'] as List?)
        ?.where((a) => a != null && a['name'] != null)
        .map((a) => a['name'] as String)
        .join(', ') ?? 'Unknown Artist';

    // Parse album info
    final album = json['album'] as Map<String, dynamic>?;
    final images = album?['images'] as List?;
    String? albumArt;
    if (images != null && images.isNotEmpty) {
      final firstImage = images.first as Map<String, dynamic>?;
      albumArt = firstImage?['url'] as String?;
    }

    // Preview URL may be null for some tracks
    final previewUrl = json['preview_url'] as String?;

    return Song(
      id: json['id'] as String? ?? '',
      title: json['name'] as String? ?? 'Unknown',
      artist: artists,
      album: album?['name'] as String?,
      albumArt: albumArt,
      duration: Duration(milliseconds: json['duration_ms'] as int? ?? 0),
      previewUrl: previewUrl,
    );
  }

  void dispose() {
    _dio.close();
  }
}
