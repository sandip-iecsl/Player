import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/song.dart';
import '../../config/lastfm_config.dart';

/// Last.fm API Service
/// Provides music recommendations, similar tracks, and trending music
/// Note: Last.fm doesn't provide streaming URLs, only metadata
/// We use it for discovery, then find the songs on JioSaavn for playback
class LastFmService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // Last.fm API - Free tier, no authentication required for basic features
  static const String _baseUrl = 'https://ws.audioscrobbler.com/2.0/';
  
  /// Search for tracks
  Future<List<Map<String, String>>> searchTracks(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    
    // Check if Last.fm is configured
    if (!LastFmConfig.isConfigured) {
      debugPrint('[Last.fm] ⚠️ API key not configured, skipping Last.fm search');
      return [];
    }
    
    debugPrint('[Last.fm] 🔍 Searching for: "$query"');

    try {
      final response = await _dio.get(
        _baseUrl,
        queryParameters: {
          'method': 'track.search',
          'track': query,
          'api_key': LastFmConfig.apiKey,
          'format': 'json',
          'limit': limit,
        },
        options: Options(
          headers: {
            'Accept': 'application/json',
          },
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final results = <Map<String, String>>[];
        
        if (data['results'] != null && 
            data['results']['trackmatches'] != null &&
            data['results']['trackmatches']['track'] != null) {
          final tracks = data['results']['trackmatches']['track'] as List;
          
          for (final track in tracks) {
            results.add({
              'name': track['name']?.toString() ?? '',
              'artist': track['artist']?.toString() ?? '',
              'album': track['album']?.toString() ?? '',
            });
          }
          
          debugPrint('[Last.fm] ✅ Found ${results.length} tracks');
        }
        
        return results;
      }
    } catch (e) {
      debugPrint('[Last.fm] ❌ Search failed: $e');
    }

    return [];
  }

  /// Get similar tracks (recommendations)
  Future<List<Map<String, String>>> getSimilarTracks(String trackName, String artistName, {int limit = 20}) async {
    if (!LastFmConfig.isConfigured) {
      debugPrint('[Last.fm] ⚠️ API key not configured, skipping similar tracks');
      return [];
    }
    
    debugPrint('[Last.fm] 🎵 Getting similar tracks for: "$trackName" by "$artistName"');

    try {
      final response = await _dio.get(
        _baseUrl,
        queryParameters: {
          'method': 'track.getSimilar',
          'track': trackName,
          'artist': artistName,
          'api_key': LastFmConfig.apiKey,
          'format': 'json',
          'limit': limit,
        },
        options: Options(
          headers: {
            'Accept': 'application/json',
          },
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final results = <Map<String, String>>[];
        
        if (data['similartracks'] != null && data['similartracks']['track'] != null) {
          final tracks = data['similartracks']['track'] as List;
          
          for (final track in tracks) {
            results.add({
              'name': track['name']?.toString() ?? '',
              'artist': track['artist']?['name']?.toString() ?? '',
            });
          }
          
          debugPrint('[Last.fm] ✅ Found ${results.length} similar tracks');
        }
        
        return results;
      }
    } catch (e) {
      debugPrint('[Last.fm] ❌ Get similar tracks failed: $e');
    }

    return [];
  }

  /// Get top tracks (trending)
  Future<List<Map<String, String>>> getTopTracks({int limit = 20}) async {
    if (!LastFmConfig.isConfigured) {
      debugPrint('[Last.fm] ⚠️ API key not configured, skipping top tracks');
      return [];
    }
    
    debugPrint('[Last.fm] 📈 Getting top tracks');

    try {
      final response = await _dio.get(
        _baseUrl,
        queryParameters: {
          'method': 'chart.getTopTracks',
          'api_key': LastFmConfig.apiKey,
          'format': 'json',
          'limit': limit,
        },
        options: Options(
          headers: {
            'Accept': 'application/json',
          },
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final results = <Map<String, String>>[];
        
        if (data['tracks'] != null && data['tracks']['track'] != null) {
          final tracks = data['tracks']['track'] as List;
          
          for (final track in tracks) {
            results.add({
              'name': track['name']?.toString() ?? '',
              'artist': track['artist']?['name']?.toString() ?? '',
            });
          }
          
          debugPrint('[Last.fm] ✅ Found ${results.length} top tracks');
        }
        
        return results;
      }
    } catch (e) {
      debugPrint('[Last.fm] ❌ Get top tracks failed: $e');
    }

    return [];
  }

  /// Get top tracks by tag/genre
  Future<List<Map<String, String>>> getTopTracksByTag(String tag, {int limit = 20}) async {
    if (!LastFmConfig.isConfigured) {
      debugPrint('[Last.fm] ⚠️ API key not configured, skipping tracks by tag');
      return [];
    }
    
    debugPrint('[Last.fm] 🏷️ Getting top tracks for tag: "$tag"');

    try {
      final response = await _dio.get(
        _baseUrl,
        queryParameters: {
          'method': 'tag.getTopTracks',
          'tag': tag,
          'api_key': LastFmConfig.apiKey,
          'format': 'json',
          'limit': limit,
        },
        options: Options(
          headers: {
            'Accept': 'application/json',
          },
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final results = <Map<String, String>>[];
        
        if (data['tracks'] != null && data['tracks']['track'] != null) {
          final tracks = data['tracks']['track'] as List;
          
          for (final track in tracks) {
            results.add({
              'name': track['name']?.toString() ?? '',
              'artist': track['artist']?['name']?.toString() ?? '',
            });
          }
          
          debugPrint('[Last.fm] ✅ Found ${results.length} tracks for tag "$tag"');
        }
        
        return results;
      }
    } catch (e) {
      debugPrint('[Last.fm] ❌ Get tracks by tag failed: $e');
    }

    return [];
  }

  /// Get top tracks by artist
  Future<List<Map<String, String>>> getArtistTopTracks(String artistName, {int limit = 20}) async {
    if (!LastFmConfig.isConfigured) {
      debugPrint('[Last.fm] ⚠️ API key not configured, skipping artist top tracks');
      return [];
    }
    
    debugPrint('[Last.fm] 🎤 Getting top tracks for artist: "$artistName"');

    try {
      final response = await _dio.get(
        _baseUrl,
        queryParameters: {
          'method': 'artist.getTopTracks',
          'artist': artistName,
          'api_key': LastFmConfig.apiKey,
          'format': 'json',
          'limit': limit,
        },
        options: Options(
          headers: {
            'Accept': 'application/json',
          },
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final results = <Map<String, String>>[];
        
        if (data['toptracks'] != null && data['toptracks']['track'] != null) {
          final tracks = data['toptracks']['track'] as List;
          
          for (final track in tracks) {
            results.add({
              'name': track['name']?.toString() ?? '',
              'artist': track['artist']?['name']?.toString() ?? artistName,
            });
          }
          
          debugPrint('[Last.fm] ✅ Found ${results.length} top tracks for artist "$artistName"');
        }
        
        return results;
      }
    } catch (e) {
      debugPrint('[Last.fm] ❌ Get artist top tracks failed: $e');
    }

    return [];
  }

  void dispose() {
    _dio.close();
  }
}
