import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/song.dart';
import 'spotify_service.dart';
import 'ml_recommendation_engine.dart';
import 'jiosaavn_adapter.dart';
import 'queue_manager.dart';

/// Unified Music Service - Combines Spotify and JioSaavn APIs
/// Provides a single interface for all music operations
/// Falls back to JioSaavn when Spotify is unavailable
enum MusicServiceProvider { spotify, jiosaavn }

class UnifiedMusicService {
  final SpotifyService _spotifyService;
  final MLRecommendationEngine _jiosaavnEngine;
  late final JioSaavnAdapter _jiosaavnAdapter;
  late final QueueManager queueManager;

  MusicServiceProvider _activeProvider = MusicServiceProvider.jiosaavn;

  UnifiedMusicService({
    required SpotifyService spotifyService,
    required MLRecommendationEngine jiosaavnEngine,
  })  : _spotifyService = spotifyService,
        _jiosaavnEngine = jiosaavnEngine {
    _jiosaavnAdapter = JioSaavnAdapter(_jiosaavnEngine);
    queueManager = QueueManager(_spotifyService);
  }

  // ============================================================================
  // PROVIDER MANAGEMENT
  // ============================================================================

  MusicServiceProvider get activeProvider => _activeProvider;
  bool get isSpotifyActive => _activeProvider == MusicServiceProvider.spotify;
  bool get isJioSaavnActive => _activeProvider == MusicServiceProvider.jiosaavn;

  /// Set Spotify as active provider (requires authentication)
  void activateSpotify(String accessToken, {Duration expiresIn = const Duration(hours: 1)}) {
    _spotifyService.setAccessToken(accessToken, expiresIn: expiresIn);
    _activeProvider = MusicServiceProvider.spotify;
    debugPrint('[UnifiedMusic] ✅ Spotify activated');
  }

  /// Switch to JioSaavn provider
  void activateJioSaavn() {
    _activeProvider = MusicServiceProvider.jiosaavn;
    debugPrint('[UnifiedMusic] ✅ JioSaavn activated');
  }

  // ============================================================================
  // SEARCH
  // ============================================================================

  /// Universal search across active provider
  Future<UnifiedSearchResults> search(String query, {int limit = 20}) async {
    debugPrint('[UnifiedMusic] 🔍 Searching: "$query" (provider: $_activeProvider)');

    try {
      if (_activeProvider == MusicServiceProvider.spotify && _spotifyService.isAuthenticated) {
        return await _searchSpotify(query, limit: limit);
      } else {
        return await _searchJioSaavn(query, limit: limit);
      }
    } catch (e) {
      debugPrint('[UnifiedMusic] ❌ Search failed on $_activeProvider: $e');
      
      // Fallback to JioSaavn if Spotify fails
      if (_activeProvider == MusicServiceProvider.spotify) {
        debugPrint('[UnifiedMusic] 🔄 Falling back to JioSaavn...');
        return await _searchJioSaavn(query, limit: limit);
      }
      
      rethrow;
    }
  }

  Future<UnifiedSearchResults> _searchSpotify(String query, {int limit = 20}) async {
    final results = await _spotifyService.search(
      query: query,
      types: ['track', 'album', 'artist'],
      limit: limit,
    );

    return UnifiedSearchResults(
      tracks: results.tracks,
      albums: results.albums.map((a) => UnifiedAlbum(
        id: a.id,
        name: a.name,
        artist: a.artist,
        coverArt: a.coverArt,
        totalTracks: a.totalTracks,
        provider: MusicServiceProvider.spotify,
      )).toList(),
      artists: results.artists.map((a) => UnifiedArtist(
        id: a.id,
        name: a.name,
        imageUrl: a.imageUrl,
        genres: a.genres,
        provider: MusicServiceProvider.spotify,
      )).toList(),
      provider: MusicServiceProvider.spotify,
    );
  }

  Future<UnifiedSearchResults> _searchJioSaavn(String query, {int limit = 20}) async {
    final tracks = await _jiosaavnEngine.searchSongs(query, limit: limit);

    return UnifiedSearchResults(
      tracks: tracks,
      albums: [], // JioSaavn search doesn't return albums separately
      artists: [], // JioSaavn search doesn't return artists separately
      provider: MusicServiceProvider.jiosaavn,
    );
  }

  // ============================================================================
  // PLAYBACK INITIALIZATION
  // ============================================================================

  /// Initialize playback from search query
  Future<Song> playFromSearch(String query, {int recommendationLimit = 20}) async {
    debugPrint('[UnifiedMusic] ▶️ Play from search: "$query"');

    if (_activeProvider == MusicServiceProvider.spotify && _spotifyService.isAuthenticated) {
      return await queueManager.initializeFromSearch(query, recommendationLimit: recommendationLimit);
    } else {
      // JioSaavn flow: search + ML recommendations
      final searchResults = await _searchJioSaavn(query, limit: 1);
      if (searchResults.tracks.isEmpty) {
        throw Exception('No tracks found for query: $query');
      }

      // Use JioSaavn adapter to generate queue
      final result = await _jiosaavnAdapter.searchAndGenerateQueue(
        query: query,
        recommendationLimit: recommendationLimit,
      );

      // Set queue state using the public method
      queueManager.setQueueState(
        originalQueue: result.queue,
        activeQueue: List.from(result.queue),
        currentIndex: result.currentIndex,
        context: PlaybackContext.search,
        contextId: null,
        isShuffled: false,
        hasTransitionedToRadio: false,
      );

      return result.targetTrack;
    }
  }

  /// Initialize playback from album
  Future<Song> playFromAlbum({
    required String albumId,
    bool shuffle = false,
    int? startTrackIndex,
  }) async {
    debugPrint('[UnifiedMusic] ▶️ Play from album: $albumId');

    if (_activeProvider == MusicServiceProvider.spotify && _spotifyService.isAuthenticated) {
      return await queueManager.initializeFromAlbum(
        albumId: albumId,
        shuffle: shuffle,
        startTrackIndex: startTrackIndex,
      );
    } else {
      throw Exception('Album playback requires Spotify authentication');
    }
  }

  /// Initialize playback from artist
  Future<Song> playFromArtist({
    required String artistId,
    String market = 'IN',
  }) async {
    debugPrint('[UnifiedMusic] ▶️ Play from artist: $artistId');

    if (_activeProvider == MusicServiceProvider.spotify && _spotifyService.isAuthenticated) {
      return await queueManager.initializeFromArtist(
        artistId: artistId,
        market: market,
      );
    } else {
      throw Exception('Artist playback requires Spotify authentication');
    }
  }

  // ============================================================================
  // RECOMMENDATIONS
  // ============================================================================

  /// Get recommendations based on seed song
  Future<List<Song>> getRecommendations({
    required Song seedSong,
    int limit = 20,
  }) async {
    debugPrint('[UnifiedMusic] 🎯 Getting recommendations for: ${seedSong.title}');

    if (_activeProvider == MusicServiceProvider.spotify && _spotifyService.isAuthenticated) {
      return await _spotifyService.getRecommendations(
        seedTracks: [seedSong.id],
        limit: limit,
      );
    } else {
      return await _jiosaavnEngine.deliverRecommendations(
        seedSong: seedSong,
        limit: limit,
      );
    }
  }

  // ============================================================================
  // ALBUM & ARTIST DETAILS
  // ============================================================================

  /// Get new releases (Spotify only)
  Future<List<UnifiedAlbum>> getNewReleases({
    String country = 'IN',
    int limit = 20,
  }) async {
    if (_activeProvider == MusicServiceProvider.spotify && _spotifyService.isAuthenticated) {
      final albums = await _spotifyService.getNewReleases(
        country: country,
        limit: limit,
      );
      return albums.map((a) => UnifiedAlbum(
        id: a.id,
        name: a.name,
        artist: a.artist,
        coverArt: a.coverArt,
        totalTracks: a.totalTracks,
        provider: MusicServiceProvider.spotify,
      )).toList();
    }
    
    // Fallback to JioSaavn new releases
    debugPrint('[UnifiedMusic] 🔄 Fetching new releases from JioSaavn...');
    final tracks = await _jiosaavnEngine.searchSongs('new releases', limit: limit);
    
    // Group tracks by album (if available)
    final Map<String, List<Song>> albumGroups = {};
    for (final track in tracks) {
      final albumName = track.album ?? 'Unknown Album';
      albumGroups.putIfAbsent(albumName, () => []).add(track);
    }
    
    // Convert to unified albums
    return albumGroups.entries.map((entry) {
      final firstTrack = entry.value.first;
      return UnifiedAlbum(
        id: firstTrack.id,
        name: entry.key,
        artist: firstTrack.artist,
        coverArt: firstTrack.albumArt,
        totalTracks: entry.value.length,
        provider: MusicServiceProvider.jiosaavn,
      );
    }).toList();
  }

  /// Get album details
  Future<UnifiedAlbum?> getAlbum(String albumId) async {
    if (_activeProvider == MusicServiceProvider.spotify && _spotifyService.isAuthenticated) {
      final album = await _spotifyService.getAlbum(albumId);
      return UnifiedAlbum(
        id: album.id,
        name: album.name,
        artist: album.artist,
        coverArt: album.coverArt,
        totalTracks: album.totalTracks,
        provider: MusicServiceProvider.spotify,
      );
    }
    return null;
  }

  /// Get multiple albums at once (Spotify only)
  Future<List<UnifiedAlbum>> getSeveralAlbums(List<String> albumIds) async {
    if (_activeProvider == MusicServiceProvider.spotify && _spotifyService.isAuthenticated) {
      final albums = await _spotifyService.getSeveralAlbums(albumIds);
      return albums.map((a) => UnifiedAlbum(
        id: a.id,
        name: a.name,
        artist: a.artist,
        coverArt: a.coverArt,
        totalTracks: a.totalTracks,
        provider: MusicServiceProvider.spotify,
      )).toList();
    }
    return [];
  }

  /// Get artist details
  Future<UnifiedArtist?> getArtist(String artistId) async {
    if (_activeProvider == MusicServiceProvider.spotify && _spotifyService.isAuthenticated) {
      final artist = await _spotifyService.getArtist(artistId);
      return UnifiedArtist(
        id: artist.id,
        name: artist.name,
        imageUrl: artist.imageUrl,
        genres: artist.genres,
        provider: MusicServiceProvider.spotify,
      );
    }
    return null;
  }

  // ============================================================================
  // ANALYTICS (JioSaavn ML Engine)
  // ============================================================================

  /// Track song play for ML learning (JioSaavn only)
  void trackSongPlay(Song song, {required double completionRate}) {
    if (_activeProvider == MusicServiceProvider.jiosaavn) {
      _jiosaavnEngine.trackSongPlay(song, completionRate: completionRate);
      debugPrint('[UnifiedMusic] 📊 Tracked play: ${song.title} (${(completionRate * 100).toStringAsFixed(0)}%)');
    }
  }

  // ============================================================================
  // PLAYBACK & DEVICE MANAGEMENT (Spotify only)
  // ============================================================================

  /// Get available playback devices (Spotify only)
  Future<List<SpotifyDevice>> getAvailableDevices() async {
    if (_activeProvider == MusicServiceProvider.spotify && _spotifyService.isAuthenticated) {
      return await _spotifyService.getAvailableDevices();
    }
    return [];
  }

  /// Get user's current playback queue (Spotify only)
  Future<SpotifyQueue?> getUserQueue() async {
    if (_activeProvider == MusicServiceProvider.spotify && _spotifyService.isAuthenticated) {
      return await _spotifyService.getUserQueue();
    }
    return null;
  }

  // ============================================================================
  // BROWSE & CATEGORIES (Spotify only)
  // ============================================================================

  /// Get browse categories (Spotify only)
  Future<List<SpotifyCategory>> getBrowseCategories({
    String country = 'IN',
    String locale = 'en_IN',
    int limit = 20,
  }) async {
    if (_activeProvider == MusicServiceProvider.spotify && _spotifyService.isAuthenticated) {
      return await _spotifyService.getBrowseCategories(
        country: country,
        locale: locale,
        limit: limit,
      );
    }
    return [];
  }

  // ============================================================================
  // PROVIDER INFO
  // ============================================================================

  Map<String, dynamic> getProviderInfo() {
    return {
      'activeProvider': _activeProvider.toString(),
      'spotifyAuthenticated': _spotifyService.isAuthenticated,
      'queueInfo': queueManager.getQueueInfo(),
    };
  }

  void dispose() {
    queueManager.dispose();
    _spotifyService.dispose();
    _jiosaavnEngine.dispose();
  }
}

// ============================================================================
// UNIFIED DATA MODELS
// ============================================================================

class UnifiedSearchResults {
  final List<Song> tracks;
  final List<UnifiedAlbum> albums;
  final List<UnifiedArtist> artists;
  final MusicServiceProvider provider;

  UnifiedSearchResults({
    required this.tracks,
    required this.albums,
    required this.artists,
    required this.provider,
  });
}

class UnifiedAlbum {
  final String id;
  final String name;
  final String artist;
  final String? coverArt;
  final int totalTracks;
  final MusicServiceProvider provider;

  UnifiedAlbum({
    required this.id,
    required this.name,
    required this.artist,
    this.coverArt,
    required this.totalTracks,
    required this.provider,
  });
}

class UnifiedArtist {
  final String id;
  final String name;
  final String? imageUrl;
  final List<String> genres;
  final MusicServiceProvider provider;

  UnifiedArtist({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.genres,
    required this.provider,
  });
}
