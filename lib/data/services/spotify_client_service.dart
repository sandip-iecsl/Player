import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../config/spotify_config.dart';
import '../../domain/entities/song.dart';

/// Spotify Web API — Client Credentials flow
/// No user login required. Auto-refreshes token every hour.
class SpotifyClientService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  static const String _api   = 'https://api.spotify.com/v1';
  static const String _token = 'https://accounts.spotify.com/api/token';

  String?   _accessToken;
  DateTime? _tokenExpiry;

  // ─── Auth ─────────────────────────────────────────────────────────────────

  Future<String?> _getToken() async {
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken;
    }
    return _refreshToken();
  }

  Future<String?> _refreshToken() async {
    try {
      final creds = base64.encode(
        utf8.encode('${SpotifyConfig.clientId}:${SpotifyConfig.clientSecret}'),
      );
      final res = await _dio.post(
        _token,
        data: 'grant_type=client_credentials',
        options: Options(headers: {
          'Authorization': 'Basic $creds',
          'Content-Type': 'application/x-www-form-urlencoded',
        }),
      );
      if (res.statusCode == 200) {
        _accessToken = res.data['access_token'] as String;
        final exp = res.data['expires_in'] as int? ?? 3600;
        _tokenExpiry = DateTime.now().add(Duration(seconds: exp - 60));
        debugPrint('[Spotify] ✅ Token refreshed');
        return _accessToken;
      }
    } catch (e) {
      debugPrint('[Spotify] ❌ Token refresh failed: $e');
    }
    return null;
  }

  Future<Options> _auth() async {
    final t = await _getToken();
    return Options(
      headers: {'Authorization': 'Bearer $t'},
      validateStatus: (s) => s != null && s < 500,
    );
  }

  // ─── Search ───────────────────────────────────────────────────────────────

  Future<List<SpotifyTrack>> searchTracks(String query, {int limit = 20, int offset = 0}) async {
    if (query.trim().isEmpty) return [];
    debugPrint('[Spotify] 🔍 Searching: "$query" (limit: $limit, offset: $offset)');
    try {
      final res = await _dio.get('$_api/search',
          queryParameters: {
            'q': query,
            'type': 'track',
            'limit': limit,
            'offset': offset,
            'market': 'IN'
          },
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['tracks']?['items'] as List? ?? [];
        final tracks = items.whereType<Map<String, dynamic>>().map(SpotifyTrack.fromJson).toList();
        debugPrint('[Spotify] ✅ Found ${tracks.length} tracks');
        return tracks;
      }
      debugPrint('[Spotify] ⚠️ Search ${res.statusCode}: ${res.data}');
    } catch (e) {
      debugPrint('[Spotify] ❌ Search error: $e');
    }
    return [];
  }

  // ─── Recommendations ──────────────────────────────────────────────────────

  Future<List<SpotifyTrack>> getRecommendations({
    List<String> seedTrackIds  = const [],
    List<String> seedArtistIds = const [],
    List<String> seedGenres    = const [],
    int limit = 20,
  }) async {
    debugPrint('[Spotify] 🎵 Getting recommendations');
    try {
      final params = <String, dynamic>{'limit': limit, 'market': 'IN'};
      if (seedTrackIds.isNotEmpty)  params['seed_tracks']  = seedTrackIds.take(2).join(',');
      if (seedArtistIds.isNotEmpty) params['seed_artists'] = seedArtistIds.take(2).join(',');
      if (seedGenres.isNotEmpty)    params['seed_genres']  = seedGenres.take(1).join(',');

      final res = await _dio.get('$_api/recommendations',
          queryParameters: params, options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['tracks'] as List? ?? [];
        final tracks = items.whereType<Map<String, dynamic>>().map(SpotifyTrack.fromJson).toList();
        debugPrint('[Spotify] ✅ Got ${tracks.length} recommendations');
        return tracks;
      }
      debugPrint('[Spotify] ⚠️ Recommendations ${res.statusCode}: ${res.data}');
    } catch (e) {
      debugPrint('[Spotify] ❌ Recommendations error: $e');
    }
    return [];
  }

  // ─── Albums ───────────────────────────────────────────────────────────────

  /// Get multiple albums by IDs
  Future<List<SpotifyAlbum>> getAlbums(List<String> albumIds) async {
    if (albumIds.isEmpty) return [];
    try {
      final res = await _dio.get('$_api/albums',
          queryParameters: {'ids': albumIds.take(20).join(','), 'market': 'IN'},
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['albums'] as List? ?? [];
        return items.whereType<Map<String, dynamic>>().map(SpotifyAlbum.fromJson).toList();
      }
    } catch (e) {
      debugPrint('[Spotify] ❌ Get albums error: $e');
    }
    return [];
  }

  /// Get tracks from a single album
  Future<List<SpotifyTrack>> getAlbumTracks(String albumId) async {
    try {
      final res = await _dio.get('$_api/albums/$albumId/tracks',
          queryParameters: {'limit': 50, 'market': 'IN'},
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['items'] as List? ?? [];
        return items.whereType<Map<String, dynamic>>().map(SpotifyTrack.fromJson).toList();
      }
    } catch (e) {
      debugPrint('[Spotify] ❌ Album tracks error: $e');
    }
    return [];
  }

  // ─── Artists ──────────────────────────────────────────────────────────────

  /// Get multiple artists by IDs
  Future<List<SpotifyArtist>> getArtists(List<String> artistIds) async {
    if (artistIds.isEmpty) return [];
    try {
      final res = await _dio.get('$_api/artists',
          queryParameters: {'ids': artistIds.take(50).join(',')},
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['artists'] as List? ?? [];
        return items.whereType<Map<String, dynamic>>().map(SpotifyArtist.fromJson).toList();
      }
    } catch (e) {
      debugPrint('[Spotify] ❌ Get artists error: $e');
    }
    return [];
  }

  /// Search for a single artist, return their ID
  Future<String?> searchArtistId(String name) async {
    try {
      final res = await _dio.get('$_api/search',
          queryParameters: {'q': name, 'type': 'artist', 'limit': 1},
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['artists']?['items'] as List? ?? [];
        if (items.isNotEmpty) return items.first['id'] as String?;
      }
    } catch (e) {
      debugPrint('[Spotify] ❌ Artist search error: $e');
    }
    return null;
  }

  /// Get artist's albums
  Future<List<SpotifyAlbum>> getArtistAlbums(String artistId, {int limit = 20}) async {
    try {
      final res = await _dio.get('$_api/artists/$artistId/albums',
          queryParameters: {
            'limit': limit,
            'market': 'IN',
            'include_groups': 'album,single',
          },
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['items'] as List? ?? [];
        return items.whereType<Map<String, dynamic>>().map(SpotifyAlbum.fromJson).toList();
      }
    } catch (e) {
      debugPrint('[Spotify] ❌ Artist albums error: $e');
    }
    return [];
  }

  /// Get artist's top tracks
  Future<List<SpotifyTrack>> getArtistTopTracks(String artistId, {int limit = 50}) async {
    try {
      final res = await _dio.get('$_api/artists/$artistId/top-tracks',
          queryParameters: {'market': 'IN'},
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['tracks'] as List? ?? [];
        final tracks = items.whereType<Map<String, dynamic>>().map(SpotifyTrack.fromJson).toList();
        // Spotify returns max 10 top tracks per artist, but we return up to limit
        return tracks.take(limit).toList();
      }
    } catch (e) {
      debugPrint('[Spotify] ❌ Artist top tracks error: $e');
    }
    return [];
  }

  /// Get related artists
  Future<List<SpotifyArtist>> getRelatedArtists(String artistId) async {
    try {
      final res = await _dio.get('$_api/artists/$artistId/related-artists',
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['artists'] as List? ?? [];
        return items.whereType<Map<String, dynamic>>().map(SpotifyArtist.fromJson).toList();
      }
    } catch (e) {
      debugPrint('[Spotify] ❌ Related artists error: $e');
    }
    return [];
  }

  // ─── Browse ───────────────────────────────────────────────────────────────

  /// Get featured playlists (for home screen)
  Future<List<SpotifyPlaylist>> getFeaturedPlaylists({int limit = 20}) async {
    try {
      final res = await _dio.get('$_api/browse/featured-playlists',
          queryParameters: {'limit': limit, 'market': 'IN'},
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['playlists']?['items'] as List? ?? [];
        return items.whereType<Map<String, dynamic>>().map(SpotifyPlaylist.fromJson).toList();
      }
      debugPrint('[Spotify] ⚠️ Featured playlists ${res.statusCode}: ${res.data}');
    } catch (e) {
      debugPrint('[Spotify] ❌ Featured playlists error: $e');
    }
    return [];
  }

  /// Get browse categories
  Future<List<SpotifyCategory>> getCategories({int limit = 20}) async {
    try {
      final res = await _dio.get('$_api/browse/categories',
          queryParameters: {'limit': limit, 'market': 'IN', 'locale': 'en_IN'},
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['categories']?['items'] as List? ?? [];
        return items.whereType<Map<String, dynamic>>().map(SpotifyCategory.fromJson).toList();
      }
    } catch (e) {
      debugPrint('[Spotify] ❌ Categories error: $e');
    }
    return [];
  }

  /// Get playlists for a category
  Future<List<SpotifyPlaylist>> getCategoryPlaylists(String categoryId, {int limit = 20}) async {
    try {
      final res = await _dio.get('$_api/browse/categories/$categoryId/playlists',
          queryParameters: {'limit': limit, 'market': 'IN'},
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['playlists']?['items'] as List? ?? [];
        return items.whereType<Map<String, dynamic>>().map(SpotifyPlaylist.fromJson).toList();
      }
    } catch (e) {
      debugPrint('[Spotify] ❌ Category playlists error: $e');
    }
    return [];
  }

  /// Get tracks from a playlist
  Future<List<SpotifyTrack>> getPlaylistTracks(String playlistId, {int limit = 50}) async {
    try {
      final res = await _dio.get('$_api/playlists/$playlistId/tracks',
          queryParameters: {'limit': limit, 'market': 'IN', 'fields': 'items(track)'},
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['items'] as List? ?? [];
        return items
            .whereType<Map<String, dynamic>>()
            .map((item) => item['track'] as Map<String, dynamic>?)
            .whereType<Map<String, dynamic>>()
            .map(SpotifyTrack.fromJson)
            .toList();
      }
    } catch (e) {
      debugPrint('[Spotify] ❌ Playlist tracks error: $e');
    }
    return [];
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Find Spotify track ID for a given title + artist
  Future<String?> findTrackId(String title, String artist) async {
    try {
      final res = await _dio.get('$_api/search',
          queryParameters: {'q': '$title $artist', 'type': 'track', 'limit': 1},
          options: await _auth());
      if (res.statusCode == 200) {
        final items = res.data['tracks']?['items'] as List? ?? [];
        if (items.isNotEmpty) return items.first['id'] as String?;
      }
    } catch (e) {
      debugPrint('[Spotify] ❌ Track ID lookup error: $e');
    }
    return null;
  }

  void dispose() => _dio.close();
}

// ─── Models ───────────────────────────────────────────────────────────────────

class SpotifyTrack {
  final String  id;
  final String  title;
  final String  artist;
  final String? artistId;
  final String? album;
  final String? albumId;
  final String? albumArt;
  final int     durationMs;

  const SpotifyTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId,
    this.album,
    this.albumId,
    this.albumArt,
    required this.durationMs,
  });

  factory SpotifyTrack.fromJson(Map<String, dynamic> json) {
    final artists   = json['artists'] as List? ?? [];
    final artistName = artists.isNotEmpty
        ? artists.map((a) => a['name']).join(', ')
        : 'Unknown Artist';
    final artistId  = artists.isNotEmpty ? artists.first['id'] as String? : null;

    final albumJson = json['album'] as Map<String, dynamic>?;
    final images    = albumJson?['images'] as List? ?? [];
    final albumArt  = images.isNotEmpty ? images.first['url'] as String? : null;

    return SpotifyTrack(
      id:         json['id']?.toString() ?? '',
      title:      json['name']?.toString() ?? 'Unknown',
      artist:     artistName,
      artistId:   artistId,
      album:      albumJson?['name']?.toString(),
      albumId:    albumJson?['id']?.toString(),
      albumArt:   albumArt,
      durationMs: json['duration_ms'] as int? ?? 0,
    );
  }

  Song toSong({String? previewUrl}) => Song(
    id:         id,
    title:      title,
    artist:     artist,
    album:      album,
    albumArt:   albumArt,
    duration:   Duration(milliseconds: durationMs),
    previewUrl: previewUrl,
  );
}

class SpotifyAlbum {
  final String        id;
  final String        name;
  final String        artist;
  final String?       albumArt;
  final String?       releaseDate;
  final int           totalTracks;
  final List<String>  trackIds;

  const SpotifyAlbum({
    required this.id,
    required this.name,
    required this.artist,
    this.albumArt,
    this.releaseDate,
    required this.totalTracks,
    this.trackIds = const [],
  });

  factory SpotifyAlbum.fromJson(Map<String, dynamic> json) {
    final artists  = json['artists'] as List? ?? [];
    final artist   = artists.isNotEmpty ? artists.first['name'] as String? ?? '' : '';
    final images   = json['images'] as List? ?? [];
    final albumArt = images.isNotEmpty ? images.first['url'] as String? : null;

    // Tracks may be embedded (when fetching full album)
    final tracksJson = json['tracks']?['items'] as List? ?? [];
    final trackIds   = tracksJson
        .whereType<Map<String, dynamic>>()
        .map((t) => t['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    return SpotifyAlbum(
      id:          json['id']?.toString() ?? '',
      name:        json['name']?.toString() ?? 'Unknown Album',
      artist:      artist,
      albumArt:    albumArt,
      releaseDate: json['release_date']?.toString(),
      totalTracks: json['total_tracks'] as int? ?? 0,
      trackIds:    trackIds,
    );
  }
}

class SpotifyArtist {
  final String       id;
  final String       name;
  final String?      imageUrl;
  final List<String> genres;
  final int          popularity;

  const SpotifyArtist({
    required this.id,
    required this.name,
    this.imageUrl,
    this.genres = const [],
    this.popularity = 0,
  });

  factory SpotifyArtist.fromJson(Map<String, dynamic> json) {
    final images   = json['images'] as List? ?? [];
    final imageUrl = images.isNotEmpty ? images.first['url'] as String? : null;
    final genres   = (json['genres'] as List? ?? []).cast<String>();

    return SpotifyArtist(
      id:         json['id']?.toString() ?? '',
      name:       json['name']?.toString() ?? 'Unknown Artist',
      imageUrl:   imageUrl,
      genres:     genres,
      popularity: json['popularity'] as int? ?? 0,
    );
  }
}

class SpotifyPlaylist {
  final String  id;
  final String  name;
  final String? description;
  final String? imageUrl;

  const SpotifyPlaylist({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
  });

  factory SpotifyPlaylist.fromJson(Map<String, dynamic> json) {
    final images   = json['images'] as List? ?? [];
    final imageUrl = images.isNotEmpty ? images.first['url'] as String? : null;

    return SpotifyPlaylist(
      id:          json['id']?.toString() ?? '',
      name:        json['name']?.toString() ?? 'Unknown Playlist',
      description: json['description']?.toString(),
      imageUrl:    imageUrl,
    );
  }
}

class SpotifyCategory {
  final String  id;
  final String  name;
  final String? iconUrl;

  const SpotifyCategory({
    required this.id,
    required this.name,
    this.iconUrl,
  });

  factory SpotifyCategory.fromJson(Map<String, dynamic> json) {
    final icons   = json['icons'] as List? ?? [];
    final iconUrl = icons.isNotEmpty ? icons.first['url'] as String? : null;

    return SpotifyCategory(
      id:      json['id']?.toString() ?? '',
      name:    json['name']?.toString() ?? '',
      iconUrl: iconUrl,
    );
  }
}
