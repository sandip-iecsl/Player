import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/song.dart';

/// Spotify API Integration Service
/// Implements three main flows:
/// 1. Search-based playback with auto-recommendations
/// 2. Album playback (sequential/shuffle)
/// 3. Artist profile playback (top tracks → radio)
class SpotifyService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api.spotify.com/v1',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  String? _accessToken;
  DateTime? _tokenExpiry;

  // ============================================================================
  // AUTHENTICATION
  // ============================================================================

  /// Set Spotify access token (must be obtained via OAuth flow)
  void setAccessToken(String token, {Duration expiresIn = const Duration(hours: 1)}) {
    _accessToken = token;
    _tokenExpiry = DateTime.now().add(expiresIn);
    _dio.options.headers['Authorization'] = 'Bearer $token';
    debugPrint('[Spotify] ✅ Access token set, expires at $_tokenExpiry');
  }

  bool get isAuthenticated => _accessToken != null && 
      _tokenExpiry != null && 
      DateTime.now().isBefore(_tokenExpiry!);

  // ============================================================================
  // FLOW 1: SEARCH-BASED PLAYBACK WITH AUTO-RECOMMENDATIONS
  // ============================================================================

  /// Search for a track and generate autoplay queue
  /// Returns: [Target Track, Rec Track 1, Rec Track 2, ...]
  Future<SearchPlaybackResult> searchAndGenerateQueue({
    required String query,
    int recommendationLimit = 20,
  }) async {
    _ensureAuthenticated();
    
    debugPrint('[Spotify Flow 1] 🔍 Searching for: "$query"');

    try {
      // Step 1: FETCH TRACK
      final searchResponse = await _dio.get(
        '/search',
        queryParameters: {
          'q': query,
          'type': 'track',
          'limit': 1,
        },
      );

      final tracks = searchResponse.data['tracks']['items'] as List;
      if (tracks.isEmpty) {
        throw Exception('No tracks found for query: $query');
      }

      final targetTrack = _parseTrack(tracks.first);
      final trackId = targetTrack.id;
      
      debugPrint('[Spotify Flow 1] 🎵 Found: ${targetTrack.title} by ${targetTrack.artist}');

      // Step 2: INITIALIZE AUDIO (handled by caller with preview_url)
      
      // Step 3: GENERATE AUTOPLAY POOL
      final recommendations = await getRecommendations(
        seedTracks: [trackId],
        limit: recommendationLimit,
      );

      // Step 4: UPDATE QUEUE STATE
      final queue = [targetTrack, ...recommendations];
      
      debugPrint('[Spotify Flow 1] ✅ Generated queue with ${queue.length} tracks');

      return SearchPlaybackResult(
        targetTrack: targetTrack,
        queue: queue,
        currentIndex: 0,
      );
    } catch (e) {
      debugPrint('[Spotify Flow 1] ❌ Error: $e');
      rethrow;
    }
  }

  /// Get recommendations based on seed tracks
  /// Response format: {seeds: [], tracks: []}
  Future<List<Song>> getRecommendations({
    required List<String> seedTracks,
    int limit = 20,
  }) async {
    _ensureAuthenticated();

    try {
      final response = await _dio.get(
        '/recommendations',
        queryParameters: {
          'seed_tracks': seedTracks.join(','),
          'limit': limit,
        },
      );

      final data = response.data as Map<String, dynamic>;
      List<Song> tracks = [];
      
      // Parse tracks from response
      if (data.containsKey('tracks') && data['tracks'] != null) {
        final tracksList = data['tracks'] as List;
        tracks = tracksList
            .where((t) => t != null)
            .map((t) => _parseTrack(t as Map<String, dynamic>))
            .toList();
      }

      debugPrint('[Spotify] ✅ Got ${tracks.length} recommendations');
      return tracks;
    } catch (e) {
      debugPrint('[Spotify] ❌ Failed to get recommendations: $e');
      return [];
    }
  }

  // ============================================================================
  // FLOW 2: ALBUM PLAYBACK (SEQUENTIAL/SHUFFLE)
  // ============================================================================

  /// Fetch album tracklist and prepare for playback
  Future<AlbumPlaybackResult> fetchAlbumTracklist({
    required String albumId,
    bool shuffle = false,
    int? startTrackIndex,
  }) async {
    _ensureAuthenticated();
    
    debugPrint('[Spotify Flow 2] 💿 Fetching album: $albumId (shuffle: $shuffle)');

    try {
      // Step 1: FETCH TRACKLIST
      final response = await _dio.get(
        '/albums/$albumId/tracks',
        queryParameters: {'limit': 50},
      );

      final items = response.data['items'] as List;
      final originalQueue = items.map((t) => _parseTrack(t, albumId: albumId)).toList();
      
      debugPrint('[Spotify Flow 2] 📋 Fetched ${originalQueue.length} tracks');

      // Step 2: CHOOSE PLAYBACK MODE
      List<Song> activeQueue;
      int currentIndex;

      if (shuffle && startTrackIndex != null) {
        // CASE B: SHUFFLE PLAY
        // Lock the selected track at index 0, shuffle the rest
        final selectedTrack = originalQueue[startTrackIndex];
        final remainingTracks = List<Song>.from(originalQueue)
          ..removeAt(startTrackIndex);
        
        // Fisher-Yates shuffle
        _fisherYatesShuffle(remainingTracks);
        
        activeQueue = [selectedTrack, ...remainingTracks];
        currentIndex = 0;
        
        debugPrint('[Spotify Flow 2] 🔀 Shuffle mode: ${selectedTrack.title} locked at index 0');
      } else {
        // CASE A: SEQUENTIAL PLAY
        activeQueue = List.from(originalQueue);
        currentIndex = startTrackIndex ?? 0;
        
        debugPrint('[Spotify Flow 2] ▶️ Sequential mode: starting at index $currentIndex');
      }

      return AlbumPlaybackResult(
        originalQueue: originalQueue,
        activeQueue: activeQueue,
        currentIndex: currentIndex,
        isShuffled: shuffle,
      );
    } catch (e) {
      debugPrint('[Spotify Flow 2] ❌ Error: $e');
      rethrow;
    }
  }

  /// Fisher-Yates shuffle algorithm
  void _fisherYatesShuffle(List<Song> list) {
    final random = Random();
    for (int i = list.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }

  // ============================================================================
  // FLOW 3: ARTIST PROFILE PLAYBACK (TOP TRACKS → RADIO)
  // ============================================================================

  /// Fetch artist's top tracks and prepare for playback
  Future<ArtistPlaybackResult> fetchArtistTopTracks({
    required String artistId,
    String market = 'IN',
  }) async {
    _ensureAuthenticated();
    
    debugPrint('[Spotify Flow 3] 🎤 Fetching top tracks for artist: $artistId');

    try {
      // Step 1: FETCH POPULAR LIST
      final response = await _dio.get(
        '/artists/$artistId/top-tracks',
        queryParameters: {'market': market},
      );

      final tracks = response.data['tracks'] as List;
      final topTracks = tracks.map((t) => _parseTrack(t)).toList();
      
      debugPrint('[Spotify Flow 3] ⭐ Fetched ${topTracks.length} top tracks');

      // Step 2: CONSTRUCT BUCKET
      return ArtistPlaybackResult(
        originalQueue: List.from(topTracks),
        activeQueue: List.from(topTracks),
        currentIndex: 0,
        artistId: artistId,
        market: market,
      );
    } catch (e) {
      debugPrint('[Spotify Flow 3] ❌ Error: $e');
      rethrow;
    }
  }

  /// Transition to radio mode after top tracks finish
  /// Step 4: TRANSITION TO RADIO
  Future<List<Song>> transitionToRadio({
    required String lastTrackId,
    int limit = 20,
  }) async {
    _ensureAuthenticated();
    
    debugPrint('[Spotify Flow 3] 📻 Transitioning to radio mode from track: $lastTrackId');

    try {
      final recommendations = await getRecommendations(
        seedTracks: [lastTrackId],
        limit: limit,
      );
      
      debugPrint('[Spotify Flow 3] ✅ Radio mode: ${recommendations.length} tracks loaded');
      return recommendations;
    } catch (e) {
      debugPrint('[Spotify Flow 3] ❌ Radio transition failed: $e');
      return [];
    }
  }

  // ============================================================================
  // ADDITIONAL SPOTIFY API METHODS
  // ============================================================================

  /// Search for tracks, albums, artists, or playlists
  /// Response format: {tracks: {items: []}, artists: {items: []}, albums: {items: []}, ...}
  Future<SpotifySearchResults> search({
    required String query,
    List<String> types = const ['track', 'album', 'artist'],
    int limit = 20,
  }) async {
    _ensureAuthenticated();

    try {
      final response = await _dio.get(
        '/search',
        queryParameters: {
          'q': query,
          'type': types.join(','),
          'limit': limit,
        },
      );

      final data = response.data as Map<String, dynamic>;
      
      // Parse tracks from nested structure: tracks.items[]
      List<Song> tracks = [];
      if (data.containsKey('tracks') && data['tracks'] != null) {
        final tracksData = data['tracks'] as Map<String, dynamic>;
        if (tracksData.containsKey('items') && tracksData['items'] != null) {
          final trackItems = tracksData['items'] as List;
          tracks = trackItems
              .where((t) => t != null)
              .map((t) => _parseTrack(t as Map<String, dynamic>))
              .toList();
        }
      }

      // Parse albums from nested structure: albums.items[]
      List<AlbumDetails> albums = [];
      if (data.containsKey('albums') && data['albums'] != null) {
        final albumsData = data['albums'] as Map<String, dynamic>;
        if (albumsData.containsKey('items') && albumsData['items'] != null) {
          final albumItems = albumsData['items'] as List;
          albums = albumItems
              .where((a) => a != null)
              .map((a) => _parseAlbum(a as Map<String, dynamic>))
              .toList();
        }
      }

      // Parse artists from nested structure: artists.items[]
      List<ArtistDetails> artists = [];
      if (data.containsKey('artists') && data['artists'] != null) {
        final artistsData = data['artists'] as Map<String, dynamic>;
        if (artistsData.containsKey('items') && artistsData['items'] != null) {
          final artistItems = artistsData['items'] as List;
          artists = artistItems
              .where((a) => a != null)
              .map((a) => _parseArtist(a as Map<String, dynamic>))
              .toList();
        }
      }

      debugPrint('[Spotify] ✅ Search results: ${tracks.length} tracks, ${albums.length} albums, ${artists.length} artists');

      return SpotifySearchResults(
        tracks: tracks,
        albums: albums,
        artists: artists,
      );
    } catch (e) {
      debugPrint('[Spotify] ❌ Search failed: $e');
      rethrow;
    }
  }

  /// Get new releases from Spotify
  /// Returns: List of newly released albums
  Future<List<AlbumDetails>> getNewReleases({
    String country = 'IN',
    int limit = 20,
    int offset = 0,
  }) async {
    _ensureAuthenticated();

    try {
      final response = await _dio.get(
        '/browse/new-releases',
        queryParameters: {
          'country': country,
          'limit': limit,
          'offset': offset,
        },
      );

      final data = response.data as Map<String, dynamic>;
      List<AlbumDetails> albums = [];
      
      // Parse albums from nested structure: albums.items[]
      if (data.containsKey('albums') && data['albums'] != null) {
        final albumsData = data['albums'] as Map<String, dynamic>;
        if (albumsData.containsKey('items') && albumsData['items'] != null) {
          final albumItems = albumsData['items'] as List;
          albums = albumItems
              .where((a) => a != null)
              .map((a) => _parseAlbum(a as Map<String, dynamic>))
              .toList();
        }
      }

      debugPrint('[Spotify] ✅ Fetched ${albums.length} new releases');
      return albums;
    } catch (e) {
      debugPrint('[Spotify] ❌ Failed to get new releases: $e');
      return [];
    }
  }

  /// Get album details with tracks
  Future<AlbumDetails> getAlbum(String albumId) async {
    _ensureAuthenticated();

    try {
      final response = await _dio.get('/albums/$albumId');
      final albumData = response.data as Map<String, dynamic>;
      
      // Parse album with tracks
      final album = _parseAlbum(albumData);
      
      // Parse tracks if available
      if (albumData.containsKey('tracks') && albumData['tracks'] != null) {
        final tracksData = albumData['tracks'] as Map<String, dynamic>;
        if (tracksData.containsKey('items') && tracksData['items'] != null) {
          final trackItems = tracksData['items'] as List;
          final tracks = trackItems
              .where((t) => t != null)
              .map((t) => _parseTrack(t as Map<String, dynamic>, albumId: albumId))
              .toList();
          
          debugPrint('[Spotify] ✅ Album "${album.name}" has ${tracks.length} tracks');
        }
      }
      
      return album;
    } catch (e) {
      debugPrint('[Spotify] ❌ Failed to get album: $e');
      rethrow;
    }
  }

  /// Get multiple albums at once
  Future<List<AlbumDetails>> getSeveralAlbums(List<String> albumIds) async {
    _ensureAuthenticated();

    if (albumIds.isEmpty) return [];

    try {
      final response = await _dio.get(
        '/albums',
        queryParameters: {
          'ids': albumIds.join(','),
        },
      );

      final data = response.data as Map<String, dynamic>;
      List<AlbumDetails> albums = [];
      
      if (data.containsKey('albums') && data['albums'] != null) {
        final albumsList = data['albums'] as List;
        albums = albumsList
            .where((a) => a != null)
            .map((a) => _parseAlbum(a as Map<String, dynamic>))
            .toList();
      }

      debugPrint('[Spotify] ✅ Fetched ${albums.length} albums');
      return albums;
    } catch (e) {
      debugPrint('[Spotify] ❌ Failed to get albums: $e');
      return [];
    }
  }

  /// Get artist details
  Future<ArtistDetails> getArtist(String artistId) async {
    _ensureAuthenticated();

    try {
      final response = await _dio.get('/artists/$artistId');
      return _parseArtist(response.data);
    } catch (e) {
      debugPrint('[Spotify] ❌ Failed to get artist: $e');
      rethrow;
    }
  }

  /// Get playlist tracks
  Future<List<Song>> getPlaylistTracks(String playlistId) async {
    _ensureAuthenticated();

    try {
      final response = await _dio.get('/playlists/$playlistId/tracks');
      final items = response.data['items'] as List;
      return items
          .where((item) => item['track'] != null)
          .map((item) => _parseTrack(item['track']))
          .toList();
    } catch (e) {
      debugPrint('[Spotify] ❌ Failed to get playlist tracks: $e');
      return [];
    }
  }

  // ============================================================================
  // PLAYBACK & DEVICE MANAGEMENT
  // ============================================================================

  /// Get available playback devices
  Future<List<SpotifyDevice>> getAvailableDevices() async {
    _ensureAuthenticated();

    try {
      final response = await _dio.get('/me/player/devices');
      final data = response.data as Map<String, dynamic>;
      
      List<SpotifyDevice> devices = [];
      if (data.containsKey('devices') && data['devices'] != null) {
        final devicesList = data['devices'] as List;
        devices = devicesList
            .where((d) => d != null)
            .map((d) => _parseDevice(d as Map<String, dynamic>))
            .toList();
      }

      debugPrint('[Spotify] ✅ Found ${devices.length} available devices');
      return devices;
    } catch (e) {
      debugPrint('[Spotify] ❌ Failed to get devices: $e');
      return [];
    }
  }

  /// Get user's current playback queue
  Future<SpotifyQueue?> getUserQueue() async {
    _ensureAuthenticated();

    try {
      final response = await _dio.get('/me/player/queue');
      final data = response.data as Map<String, dynamic>;
      
      Song? currentlyPlaying;
      if (data.containsKey('currently_playing') && data['currently_playing'] != null) {
        currentlyPlaying = _parseTrack(data['currently_playing'] as Map<String, dynamic>);
      }

      List<Song> queue = [];
      if (data.containsKey('queue') && data['queue'] != null) {
        final queueList = data['queue'] as List;
        queue = queueList
            .where((t) => t != null)
            .map((t) => _parseTrack(t as Map<String, dynamic>))
            .toList();
      }

      debugPrint('[Spotify] ✅ Queue has ${queue.length} tracks');
      return SpotifyQueue(
        currentlyPlaying: currentlyPlaying,
        queue: queue,
      );
    } catch (e) {
      debugPrint('[Spotify] ❌ Failed to get queue: $e');
      return null;
    }
  }

  // ============================================================================
  // BROWSE & CATEGORIES
  // ============================================================================

  /// Get browse categories
  Future<List<SpotifyCategory>> getBrowseCategories({
    String country = 'IN',
    String locale = 'en_IN',
    int limit = 20,
    int offset = 0,
  }) async {
    _ensureAuthenticated();

    try {
      final response = await _dio.get(
        '/browse/categories',
        queryParameters: {
          'country': country,
          'locale': locale,
          'limit': limit,
          'offset': offset,
        },
      );

      final data = response.data as Map<String, dynamic>;
      List<SpotifyCategory> categories = [];
      
      if (data.containsKey('categories') && data['categories'] != null) {
        final categoriesData = data['categories'] as Map<String, dynamic>;
        if (categoriesData.containsKey('items') && categoriesData['items'] != null) {
          final categoryItems = categoriesData['items'] as List;
          categories = categoryItems
              .where((c) => c != null)
              .map((c) => _parseCategory(c as Map<String, dynamic>))
              .toList();
        }
      }

      debugPrint('[Spotify] ✅ Found ${categories.length} browse categories');
      return categories;
    } catch (e) {
      debugPrint('[Spotify] ❌ Failed to get categories: $e');
      return [];
    }
  }

  // ============================================================================
  // PARSING HELPERS
  // ============================================================================

  Song _parseTrack(Map<String, dynamic> json, {String? albumId}) {
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

  AlbumDetails _parseAlbum(Map<String, dynamic> json) {
    // Parse images
    final images = json['images'] as List?;
    String? coverArt;
    if (images != null && images.isNotEmpty) {
      final firstImage = images.first as Map<String, dynamic>?;
      coverArt = firstImage?['url'] as String?;
    }

    // Parse artists array
    final artists = (json['artists'] as List?)
        ?.where((a) => a != null && a['name'] != null)
        .map((a) => a['name'] as String)
        .join(', ') ?? 'Unknown Artist';

    return AlbumDetails(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Album',
      artist: artists,
      coverArt: coverArt,
      releaseDate: json['release_date'] as String?,
      totalTracks: json['total_tracks'] as int? ?? 0,
    );
  }

  ArtistDetails _parseArtist(Map<String, dynamic> json) {
    // Parse images
    final images = json['images'] as List?;
    String? imageUrl;
    if (images != null && images.isNotEmpty) {
      final firstImage = images.first as Map<String, dynamic>?;
      imageUrl = firstImage?['url'] as String?;
    }

    // Parse genres
    final genres = (json['genres'] as List?)
        ?.where((g) => g != null)
        .map((g) => g as String)
        .toList() ?? [];

    // Parse followers
    final followersData = json['followers'] as Map<String, dynamic>?;
    final followers = followersData?['total'] as int? ?? 0;

    return ArtistDetails(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Artist',
      imageUrl: imageUrl,
      genres: genres,
      popularity: json['popularity'] as int? ?? 0,
      followers: followers,
    );
  }

  SpotifyDevice _parseDevice(Map<String, dynamic> json) {
    return SpotifyDevice(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Device',
      type: json['type'] as String? ?? 'unknown',
      isActive: json['is_active'] as bool? ?? false,
      isPrivateSession: json['is_private_session'] as bool? ?? false,
      isRestricted: json['is_restricted'] as bool? ?? false,
      volumePercent: json['volume_percent'] as int? ?? 0,
      supportsVolume: json['supports_volume'] as bool? ?? false,
    );
  }

  SpotifyCategory _parseCategory(Map<String, dynamic> json) {
    // Parse icons
    final icons = json['icons'] as List?;
    String? iconUrl;
    if (icons != null && icons.isNotEmpty) {
      final firstIcon = icons.first as Map<String, dynamic>?;
      iconUrl = firstIcon?['url'] as String?;
    }

    return SpotifyCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Category',
      href: json['href'] as String?,
      iconUrl: iconUrl,
    );
  }

  void _ensureAuthenticated() {
    if (!isAuthenticated) {
      throw Exception('Spotify authentication required. Call setAccessToken() first.');
    }
  }

  void dispose() {
    _dio.close();
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

/// Result from Flow 1: Search-based playback
class SearchPlaybackResult {
  final Song targetTrack;
  final List<Song> queue;
  final int currentIndex;

  SearchPlaybackResult({
    required this.targetTrack,
    required this.queue,
    required this.currentIndex,
  });
}

/// Result from Flow 2: Album playback
class AlbumPlaybackResult {
  final List<Song> originalQueue;
  final List<Song> activeQueue;
  final int currentIndex;
  final bool isShuffled;

  AlbumPlaybackResult({
    required this.originalQueue,
    required this.activeQueue,
    required this.currentIndex,
    required this.isShuffled,
  });
}

/// Result from Flow 3: Artist playback
class ArtistPlaybackResult {
  final List<Song> originalQueue;
  final List<Song> activeQueue;
  final int currentIndex;
  final String artistId;
  final String market;

  ArtistPlaybackResult({
    required this.originalQueue,
    required this.activeQueue,
    required this.currentIndex,
    required this.artistId,
    required this.market,
  });
}

/// Spotify search results
class SpotifySearchResults {
  final List<Song> tracks;
  final List<AlbumDetails> albums;
  final List<ArtistDetails> artists;

  SpotifySearchResults({
    required this.tracks,
    required this.albums,
    required this.artists,
  });
}

/// Album details
class AlbumDetails {
  final String id;
  final String name;
  final String artist;
  final String? coverArt;
  final String? releaseDate;
  final int totalTracks;

  AlbumDetails({
    required this.id,
    required this.name,
    required this.artist,
    this.coverArt,
    this.releaseDate,
    required this.totalTracks,
  });
}

/// Artist details
class ArtistDetails {
  final String id;
  final String name;
  final String? imageUrl;
  final List<String> genres;
  final int popularity;
  final int followers;

  ArtistDetails({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.genres,
    required this.popularity,
    required this.followers,
  });
}

/// Spotify playback device
class SpotifyDevice {
  final String id;
  final String name;
  final String type;
  final bool isActive;
  final bool isPrivateSession;
  final bool isRestricted;
  final int volumePercent;
  final bool supportsVolume;

  SpotifyDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.isActive,
    required this.isPrivateSession,
    required this.isRestricted,
    required this.volumePercent,
    required this.supportsVolume,
  });
}

/// Spotify playback queue
class SpotifyQueue {
  final Song? currentlyPlaying;
  final List<Song> queue;

  SpotifyQueue({
    this.currentlyPlaying,
    required this.queue,
  });
}

/// Spotify browse category
class SpotifyCategory {
  final String id;
  final String name;
  final String? href;
  final String? iconUrl;

  SpotifyCategory({
    required this.id,
    required this.name,
    this.href,
    this.iconUrl,
  });
}
