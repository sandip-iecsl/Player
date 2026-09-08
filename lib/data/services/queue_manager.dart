import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../domain/entities/song.dart';
import 'spotify_service.dart';

/// Queue Manager - Handles all playback contexts and queue operations
/// Supports three playback contexts:
/// 1. SEARCH - Search-based playback with auto-recommendations
/// 2. ALBUM - Album playback (sequential/shuffle)
/// 3. ARTIST - Artist top tracks → radio transition
enum PlaybackContext { none, search, album, artist }

enum RepeatMode { off, all, one }

class QueueManager {
  final SpotifyService _spotifyService;

  // Queue state
  List<Song> _originalQueue = [];
  List<Song> _activeQueue = [];
  int _currentIndex = 0;

  // Playback context
  PlaybackContext _context = PlaybackContext.none;
  String? _contextId; // albumId or artistId
  String _artistMarket = 'IN'; // market code for artist radio
  bool _isShuffled = false;
  RepeatMode _repeatMode = RepeatMode.off;

  // Artist context specific
  bool _hasTransitionedToRadio = false;

  // Stream controllers
  final _queueController = StreamController<List<Song>>.broadcast();
  final _currentIndexController = StreamController<int>.broadcast();
  final _contextController = StreamController<PlaybackContext>.broadcast();

  QueueManager(this._spotifyService);

  // ============================================================================
  // GETTERS
  // ============================================================================

  List<Song> get originalQueue => List.unmodifiable(_originalQueue);
  List<Song> get activeQueue => List.unmodifiable(_activeQueue);
  int get currentIndex => _currentIndex;
  Song? get currentSong => _activeQueue.isNotEmpty && _currentIndex < _activeQueue.length
      ? _activeQueue[_currentIndex]
      : null;
  PlaybackContext get context => _context;
  bool get isShuffled => _isShuffled;
  RepeatMode get repeatMode => _repeatMode;
  bool get hasNext => _currentIndex < _activeQueue.length - 1 || _repeatMode != RepeatMode.off;
  bool get hasPrevious => _currentIndex > 0 || _repeatMode != RepeatMode.off;

  // Streams
  Stream<List<Song>> get queueStream => _queueController.stream;
  Stream<int> get currentIndexStream => _currentIndexController.stream;
  Stream<PlaybackContext> get contextStream => _contextController.stream;

  // ============================================================================
  // INTERNAL QUEUE SETTER (for JioSaavn adapter)
  // ============================================================================

  /// Set queue state directly (used by JioSaavn adapter)
  void setQueueState({
    required List<Song> originalQueue,
    required List<Song> activeQueue,
    required int currentIndex,
    required PlaybackContext context,
    String? contextId,
    bool isShuffled = false,
    bool hasTransitionedToRadio = false,
  }) {
    _originalQueue = originalQueue;
    _activeQueue = activeQueue;
    _currentIndex = currentIndex;
    _context = context;
    _contextId = contextId;
    _isShuffled = isShuffled;
    _hasTransitionedToRadio = hasTransitionedToRadio;
    _notifyListeners();
  }

  // ============================================================================
  // FLOW 1: SEARCH-BASED PLAYBACK
  // ============================================================================

  /// Initialize queue from search query
  Future<Song> initializeFromSearch(String query, {int recommendationLimit = 20}) async {
    debugPrint('[QueueManager] 🔍 Initializing from search: "$query"');

    final result = await _spotifyService.searchAndGenerateQueue(
      query: query,
      recommendationLimit: recommendationLimit,
    );

    _originalQueue = result.queue;
    _activeQueue = List.from(result.queue);
    _currentIndex = result.currentIndex;
    _context = PlaybackContext.search;
    _contextId = null;
    _isShuffled = false;
    _hasTransitionedToRadio = false;

    _notifyListeners();

    debugPrint('[QueueManager] ✅ Search queue initialized: ${_activeQueue.length} tracks');
    return result.targetTrack;
  }

  // ============================================================================
  // FLOW 2: ALBUM PLAYBACK
  // ============================================================================

  /// Initialize queue from album
  Future<Song> initializeFromAlbum({
    required String albumId,
    bool shuffle = false,
    int? startTrackIndex,
  }) async {
    debugPrint('[QueueManager] 💿 Initializing from album: $albumId (shuffle: $shuffle)');

    final result = await _spotifyService.fetchAlbumTracklist(
      albumId: albumId,
      shuffle: shuffle,
      startTrackIndex: startTrackIndex,
    );

    _originalQueue = result.originalQueue;
    _activeQueue = result.activeQueue;
    _currentIndex = result.currentIndex;
    _context = PlaybackContext.album;
    _contextId = albumId;
    _isShuffled = result.isShuffled;
    _hasTransitionedToRadio = false;

    _notifyListeners();

    debugPrint('[QueueManager] ✅ Album queue initialized: ${_activeQueue.length} tracks');
    return _activeQueue[_currentIndex];
  }

  // ============================================================================
  // FLOW 3: ARTIST PLAYBACK
  // ============================================================================

  /// Initialize queue from artist's top tracks
  Future<Song> initializeFromArtist({
    required String artistId,
    String market = 'IN',
  }) async {
    debugPrint('[QueueManager] 🎤 Initializing from artist: $artistId');

    final result = await _spotifyService.fetchArtistTopTracks(
      artistId: artistId,
      market: market,
    );

    _originalQueue = result.originalQueue;
    _activeQueue = result.activeQueue;
    _currentIndex = result.currentIndex;
    _context = PlaybackContext.artist;
    _contextId = artistId;
    _artistMarket = market;
    _isShuffled = false;
    _hasTransitionedToRadio = false;

    _notifyListeners();

    debugPrint('[QueueManager] ✅ Artist queue initialized: ${_activeQueue.length} tracks');
    return _activeQueue[_currentIndex];
  }

  /// Transition to radio mode (called when top tracks finish)
  Future<void> _transitionToRadio() async {
    if (_context != PlaybackContext.artist || _hasTransitionedToRadio) {
      return;
    }

    debugPrint('[QueueManager] 📻 Transitioning to radio mode...');

    final lastTrackId = _activeQueue.last.id;
    final radioTracks = await _spotifyService.transitionToRadio(
      lastTrackId: lastTrackId,
      limit: 20,
    );

    if (radioTracks.isNotEmpty) {
      _originalQueue.clear(); // Clear original queue in radio mode
      _activeQueue.addAll(radioTracks);
      _hasTransitionedToRadio = true;
      _context = PlaybackContext.none; // Context becomes NONE in radio mode

      _notifyListeners();

      debugPrint('[QueueManager] ✅ Radio mode activated: ${radioTracks.length} tracks added');
    }
  }

  // ============================================================================
  // QUEUE NAVIGATION
  // ============================================================================

  /// Move to next track
  Future<Song?> next() async {
    if (_activeQueue.isEmpty) return null;

    // Check if we need to transition to radio (artist context)
    if (_context == PlaybackContext.artist &&
        !_hasTransitionedToRadio &&
        _currentIndex == _activeQueue.length - 1 &&
        _repeatMode == RepeatMode.off) {
      await _transitionToRadio();
    }

    // Handle repeat modes
    if (_repeatMode == RepeatMode.one) {
      // Stay on current track
      _notifyListeners();
      return currentSong;
    }

    if (_currentIndex < _activeQueue.length - 1) {
      _currentIndex++;
    } else if (_repeatMode == RepeatMode.all) {
      _currentIndex = 0;
    } else {
      // End of queue, no repeat
      debugPrint('[QueueManager] ⏹️ End of queue reached');
      return null;
    }

    _notifyListeners();
    debugPrint('[QueueManager] ⏭️ Next: ${currentSong?.title} (index: $_currentIndex)');
    return currentSong;
  }

  /// Move to previous track
  Song? previous() {
    if (_activeQueue.isEmpty) return null;

    if (_repeatMode == RepeatMode.one) {
      // Stay on current track
      _notifyListeners();
      return currentSong;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
    } else if (_repeatMode == RepeatMode.all) {
      _currentIndex = _activeQueue.length - 1;
    } else {
      // Already at start
      _currentIndex = 0;
    }

    _notifyListeners();
    debugPrint('[QueueManager] ⏮️ Previous: ${currentSong?.title} (index: $_currentIndex)');
    return currentSong;
  }

  /// Jump to specific index
  Song? jumpTo(int index) {
    if (index < 0 || index >= _activeQueue.length) {
      debugPrint('[QueueManager] ⚠️ Invalid index: $index');
      return null;
    }

    _currentIndex = index;
    _notifyListeners();
    debugPrint('[QueueManager] 🎯 Jumped to: ${currentSong?.title} (index: $_currentIndex)');
    return currentSong;
  }

  // ============================================================================
  // SHUFFLE & REPEAT
  // ============================================================================

  /// Toggle shuffle mode
  void toggleShuffle() {
    if (_activeQueue.isEmpty) return;

    _isShuffled = !_isShuffled;

    if (_isShuffled) {
      // Save current song
      final currentSong = _activeQueue[_currentIndex];

      // Shuffle the queue
      final shuffled = List<Song>.from(_activeQueue);
      _fisherYatesShuffle(shuffled);

      // Ensure current song stays at current position
      final currentSongNewIndex = shuffled.indexOf(currentSong);
      if (currentSongNewIndex != _currentIndex) {
        shuffled.removeAt(currentSongNewIndex);
        shuffled.insert(_currentIndex, currentSong);
      }

      _activeQueue = shuffled;
      debugPrint('[QueueManager] 🔀 Shuffle ON');
    } else {
      // Restore original queue
      if (_originalQueue.isNotEmpty) {
        final currentSong = _activeQueue[_currentIndex];
        _activeQueue = List.from(_originalQueue);
        _currentIndex = _activeQueue.indexOf(currentSong);
        if (_currentIndex == -1) _currentIndex = 0;
        debugPrint('[QueueManager] 🔀 Shuffle OFF - restored original order');
      }
    }

    _notifyListeners();
  }

  /// Cycle through repeat modes: OFF → ALL → ONE → OFF
  void cycleRepeatMode() {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.all;
        debugPrint('[QueueManager] 🔁 Repeat: ALL');
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
        debugPrint('[QueueManager] 🔂 Repeat: ONE');
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.off;
        debugPrint('[QueueManager] ➡️ Repeat: OFF');
        break;
    }
    _notifyListeners();
  }

  /// Set specific repeat mode
  void setRepeatMode(RepeatMode mode) {
    _repeatMode = mode;
    _notifyListeners();
    debugPrint('[QueueManager] 🔁 Repeat mode set to: $mode');
  }

  // ============================================================================
  // QUEUE MANIPULATION
  // ============================================================================

  /// Add song to queue (next in line)
  void addNext(Song song) {
    if (_activeQueue.isEmpty) {
      _activeQueue.add(song);
      _currentIndex = 0;
    } else {
      _activeQueue.insert(_currentIndex + 1, song);
    }
    _notifyListeners();
    debugPrint('[QueueManager] ➕ Added next: ${song.title}');
  }

  /// Add song to end of queue
  void addToEnd(Song song) {
    _activeQueue.add(song);
    _notifyListeners();
    debugPrint('[QueueManager] ➕ Added to end: ${song.title}');
  }

  /// Remove song from queue
  void remove(int index) {
    if (index < 0 || index >= _activeQueue.length) return;

    final removed = _activeQueue.removeAt(index);
    
    // Adjust current index if needed
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex && _currentIndex >= _activeQueue.length) {
      _currentIndex = max(0, _activeQueue.length - 1);
    }

    _notifyListeners();
    debugPrint('[QueueManager] ➖ Removed: ${removed.title}');
  }

  /// Clear entire queue
  void clear() {
    _originalQueue.clear();
    _activeQueue.clear();
    _currentIndex = 0;
    _context = PlaybackContext.none;
    _contextId = null;
    _isShuffled = false;
    _hasTransitionedToRadio = false;
    _notifyListeners();
    debugPrint('[QueueManager] 🗑️ Queue cleared');
  }

  /// Move song within queue
  void move(int from, int to) {
    if (from < 0 || from >= _activeQueue.length || to < 0 || to >= _activeQueue.length) {
      return;
    }

    final song = _activeQueue.removeAt(from);
    _activeQueue.insert(to, song);

    // Adjust current index
    if (from == _currentIndex) {
      _currentIndex = to;
    } else if (from < _currentIndex && to >= _currentIndex) {
      _currentIndex--;
    } else if (from > _currentIndex && to <= _currentIndex) {
      _currentIndex++;
    }

    _notifyListeners();
    debugPrint('[QueueManager] 🔄 Moved: ${song.title} from $from to $to');
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  void _fisherYatesShuffle(List<Song> list) {
    final random = Random();
    for (int i = list.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }

  void _notifyListeners() {
    _queueController.add(_activeQueue);
    _currentIndexController.add(_currentIndex);
    _contextController.add(_context);
  }

  // ============================================================================
  // QUEUE INFO
  // ============================================================================

  /// Get queue summary
  Map<String, dynamic> getQueueInfo() {
    return {
      'context': _context.toString(),
      'contextId': _contextId,
      'totalTracks': _activeQueue.length,
      'currentIndex': _currentIndex,
      'currentTrack': currentSong?.title,
      'isShuffled': _isShuffled,
      'repeatMode': _repeatMode.toString(),
      'hasNext': hasNext,
      'hasPrevious': hasPrevious,
      'hasTransitionedToRadio': _hasTransitionedToRadio,
    };
  }

  /// Print queue for debugging
  void printQueue() {
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('QUEUE STATE:');
    debugPrint('Context: $_context ${_contextId != null ? '($_contextId)' : ''}');
    debugPrint('Tracks: ${_activeQueue.length} | Index: $_currentIndex');
    debugPrint('Shuffle: $_isShuffled | Repeat: $_repeatMode');
    debugPrint('───────────────────────────────────────────────────────');
    for (int i = 0; i < _activeQueue.length; i++) {
      final marker = i == _currentIndex ? '▶️' : '  ';
      debugPrint('$marker ${i + 1}. ${_activeQueue[i].title} - ${_activeQueue[i].artist}');
    }
    debugPrint('═══════════════════════════════════════════════════════');
  }

  void dispose() {
    _queueController.close();
    _currentIndexController.close();
    _contextController.close();
  }
}
