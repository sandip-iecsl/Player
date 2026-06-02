import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/song.dart';

/// JioSaavn Unofficial API Service
/// Uses the unofficial JioSaavn API (https://github.com/sumitkolhe/jiosaavn-api)
/// Can be deployed to Vercel, Cloudflare Workers, or any hosting platform
/// 
/// Default: Uses public instance at saavn.dev
/// You can deploy your own instance and change the baseUrl
class JioSaavnUnofficialAPI {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // Public instance of the unofficial API
  // Using saavn.dev as primary endpoint
  static const String _baseUrl = 'https://saavn.dev/api';
  
  /// Search for songs
  Future<List<Song>> searchSongs(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    
    debugPrint('[JioSaavnAPI] 🔍 Searching for: "$query"');

    try {
      final response = await _dio.get(
        '$_baseUrl/search/songs',
        queryParameters: {
          'query': query,
          'page': 1,
          'limit': limit,
        },
        options: Options(
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'Mozilla/5.0',
          },
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      debugPrint('[JioSaavnAPI] 📡 Response status: ${response.statusCode}');
      debugPrint('[JioSaavnAPI] 📦 Response data type: ${response.data.runtimeType}');

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        
        // Check if response is valid JSON
        if (data is! Map) {
          debugPrint('[JioSaavnAPI] ❌ Invalid response format: expected Map, got ${data.runtimeType}');
          return [];
        }

        final songs = <Song>[];
        
        // Try multiple response formats
        List? results;
        
        // Format 1: data.results
        if (data['data'] != null && data['data']['results'] != null) {
          results = data['data']['results'] as List;
          debugPrint('[JioSaavnAPI] 📋 Found ${results.length} songs (format: data.results)');
        } 
        // Format 2: results
        else if (data['results'] != null) {
          results = data['results'] as List;
          debugPrint('[JioSaavnAPI] 📋 Found ${results.length} songs (format: results)');
        }
        // Format 3: data (direct array)
        else if (data['data'] != null && data['data'] is List) {
          results = data['data'] as List;
          debugPrint('[JioSaavnAPI] 📋 Found ${results.length} songs (format: data array)');
        }
        // Format 4: success + data
        else if (data['success'] == true && data['data'] != null) {
          if (data['data']['results'] != null) {
            results = data['data']['results'] as List;
          } else if (data['data'] is List) {
            results = data['data'] as List;
          }
          debugPrint('[JioSaavnAPI] 📋 Found ${results?.length ?? 0} songs (format: success.data)');
        }
        
        if (results != null && results.isNotEmpty) {
          for (final songJson in results.take(limit)) {
            try {
              if (songJson is Map<String, dynamic>) {
                final song = _parseSong(songJson);
                songs.add(song);
              }
            } catch (e, stackTrace) {
              debugPrint('[JioSaavnAPI] ⚠️ Failed to parse song: $e');
              debugPrint('[JioSaavnAPI] Stack: $stackTrace');
            }
          }
        } else {
          debugPrint('[JioSaavnAPI] ⚠️ No results found in response');
          debugPrint('[JioSaavnAPI] Response keys: ${data.keys.toList()}');
        }

        debugPrint('[JioSaavnAPI] ✅ Parsed ${songs.length} songs');
        return songs;
      } else {
        debugPrint('[JioSaavnAPI] ⚠️ Bad response: ${response.statusCode}');
        if (response.data != null) {
          debugPrint('[JioSaavnAPI] Response: ${response.data}');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[JioSaavnAPI] ❌ Search failed: $e');
      debugPrint('[JioSaavnAPI] Stack trace: $stackTrace');
    }

    return [];
  }

  /// Get song details by ID
  Future<Song?> getSongById(String songId) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/songs/$songId',
        options: Options(
          headers: {
            'Accept': 'application/json',
          },
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['data'] != null && data['data'] is List && (data['data'] as List).isNotEmpty) {
          return _parseSong(data['data'][0]);
        }
      }
    } catch (e) {
      debugPrint('[JioSaavnAPI] ❌ Failed to get song: $e');
    }

    return null;
  }

  /// Parse song from API response
  Song _parseSong(Map<String, dynamic> json) {
    try {
      // Get download URLs - prefer highest quality
      String? previewUrl;
      
      // Try downloadUrl field (array format)
      if (json['downloadUrl'] != null) {
        if (json['downloadUrl'] is List) {
          final downloads = json['downloadUrl'] as List;
          // Try to get 320kbps, then 160kbps, then any available
          for (final download in downloads.reversed) {
            if (download is Map) {
              final quality = download['quality']?.toString() ?? '';
              if (quality.contains('320') || quality.contains('160')) {
                previewUrl = download['link']?.toString() ?? download['url']?.toString();
                if (previewUrl != null) break;
              }
            }
          }
          // Fallback to last available
          if (previewUrl == null && downloads.isNotEmpty && downloads.last is Map) {
            previewUrl = downloads.last['link']?.toString() ?? downloads.last['url']?.toString();
          }
        } else if (json['downloadUrl'] is String) {
          previewUrl = json['downloadUrl'].toString();
        }
      }
      
      // Try url field (direct string)
      if (previewUrl == null && json['url'] != null) {
        previewUrl = json['url'].toString();
      }
      
      // Try media_url field
      if (previewUrl == null && json['media_url'] != null) {
        previewUrl = json['media_url'].toString();
      }

      // Get artists - try multiple fields
      String artist = 'Unknown Artist';
      if (json['primaryArtists'] != null && json['primaryArtists'].toString().isNotEmpty) {
        artist = json['primaryArtists'].toString();
      } else if (json['artist'] != null && json['artist'].toString().isNotEmpty) {
        artist = json['artist'].toString();
      } else if (json['artists'] != null) {
        if (json['artists'] is List) {
          final artists = json['artists'] as List;
          final artistNames = artists
              .where((a) => a != null)
              .map((a) {
                if (a is Map && a['name'] != null) {
                  return a['name'].toString();
                } else if (a is String) {
                  return a;
                }
                return null;
              })
              .where((name) => name != null)
              .cast<String>()
              .toList();
          if (artistNames.isNotEmpty) {
            artist = artistNames.join(', ');
          }
        } else if (json['artists'] is String) {
          artist = json['artists'].toString();
        }
      }

      // Get album art - prefer high quality
      String? albumArt;
      if (json['image'] != null) {
        if (json['image'] is List) {
          final images = json['image'] as List;
          // Get highest quality image (usually last in array)
          if (images.isNotEmpty) {
            final lastImage = images.last;
            if (lastImage is Map) {
              albumArt = lastImage['link']?.toString() ?? lastImage['url']?.toString();
            } else if (lastImage is String) {
              albumArt = lastImage;
            }
          }
        } else if (json['image'] is String) {
          albumArt = json['image'].toString();
        }
      }
      
      // Try artwork field
      if (albumArt == null && json['artwork'] != null) {
        albumArt = json['artwork'].toString();
      }

      // Get duration
      int durationSeconds = 0;
      if (json['duration'] != null) {
        if (json['duration'] is int) {
          durationSeconds = json['duration'] as int;
        } else if (json['duration'] is String) {
          durationSeconds = int.tryParse(json['duration']) ?? 0;
        }
      }
      
      // Get title
      String title = 'Unknown';
      if (json['name'] != null && json['name'].toString().isNotEmpty) {
        title = json['name'].toString();
      } else if (json['title'] != null && json['title'].toString().isNotEmpty) {
        title = json['title'].toString();
      } else if (json['song'] != null && json['song'].toString().isNotEmpty) {
        title = json['song'].toString();
      }
      
      // Get album
      String? album;
      if (json['album'] != null) {
        if (json['album'] is Map) {
          album = json['album']['name']?.toString() ?? json['album']['title']?.toString();
        } else if (json['album'] is String) {
          album = json['album'].toString();
        }
      }

      return Song(
        id: json['id']?.toString() ?? json['permaUrl']?.toString() ?? '',
        title: _cleanHtml(title),
        artist: _cleanHtml(artist),
        album: album != null ? _cleanHtml(album) : null,
        albumArt: albumArt,
        duration: Duration(seconds: durationSeconds),
        previewUrl: previewUrl,
      );
    } catch (e, stackTrace) {
      debugPrint('[JioSaavnAPI] ⚠️ Error in _parseSong: $e');
      debugPrint('[JioSaavnAPI] Stack: $stackTrace');
      debugPrint('[JioSaavnAPI] JSON keys: ${json.keys.toList()}');
      
      // Return minimal song object
      return Song(
        id: json['id']?.toString() ?? '',
        title: json['name']?.toString() ?? json['title']?.toString() ?? 'Unknown',
        artist: 'Unknown Artist',
        duration: Duration.zero,
      );
    }
  }

  /// Clean HTML entities from text
  String _cleanHtml(String text) {
    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#039;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  void dispose() {
    _dio.close();
  }
}
