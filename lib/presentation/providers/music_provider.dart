import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../domain/entities/song.dart';
import '../../data/services/unified_music_service.dart';
import '../../data/services/queue_manager.dart';

/// Music Provider - Manages playback state and integrates with UnifiedMusicService
class MusicProvider with ChangeNotifier {
  final UnifiedMusicService _musicService;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Playback state
  Song? _currentSong;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;

  // Queue state
  List<Song> _queue = [];
  int _currentIndex = 0;

  // Subscriptions
  StreamSubscription? _positionSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _queueSubscription;
  StreamSubscription? _indexSubscription;

  MusicProvider(this._musicService) {
    _initializeListeners();
  }

  // ============================================================================
  // GETTERS
  // ============================================================================

  Song? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  QueueManager get queueManager => _musicService.queueManager;
  MusicProvider get activeProvider => _musicService.activeProvider as MusicProvider;
  
  bool get hasNext => queueManager.hasNext;
  bool get hasPrevious => queueManager.hasPrevious;
  bool get isShuffled => queueManager.isShuffled;
  RepeatMode get repeatMode => queueManager.repeatMode;

  double get progress {
    if (_duration.inMilliseconds == 0) return 0.0;
    return _position.inMilliseconds / _duration.inMilliseconds;
  }

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  void _initializeListeners() {
    // Audio player listeners
    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    });

    _durationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        _duration = duration;
        notifyListeners();
      }
    });

    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      _isLoading = state.processingState == ProcessingState.loading ||
          state.processingState == ProcessingState.buffering;

      // Auto-play next when current song completes
      if (state.processingState == ProcessingState.completed) {
        _onSongCompleted();
      }

      notifyListeners();
    });

    // Queue manager listeners
    _queueSubscription = queueManager.queueStream.listen((queue) {
      _queue = queue;
      notifyListeners();
    });

    _indexSubscription = queueManager.currentIndexStream.listen((index) {
      _currentIndex = index;
      notifyListeners();
    });
  }

  // ============================================================================
  // PLAYBACK INITIALIZATION
  // ============================================================================

  /// Play from search query
  Future<void> playFromSearch(String query, {int recommendationLimit = 20}) async {
    try {
      _isLoading = true;
      notifyListeners();

      final song = await _musicService.playFromSearch(
        query,
        recommendationLimit: recommendationLimit,
      );

      await _playSong(song);
      
      debugPrint('[MusicProvider] ✅ Playing from search: ${song.title}');
    } catch (e) {
      debugPrint('[MusicProvider] ❌ Play from search failed: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Play from album
  Future<void> playFromAlbum({
    required String albumId,
    bool shuffle = false,
    int? startTrackIndex,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      final song = await _musicService.playFromAlbum(
        albumId: albumId,
        shuffle: shuffle,
        startTrackIndex: startTrackIndex,
      );

      await _playSong(song);
      
      debugPrint('[MusicProvider] ✅ Playing from album: ${song.title}');
    } catch (e) {
      debugPrint('[MusicProvider] ❌ Play from album failed: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Play from artist
  Future<void> playFromArtist({
    required String artistId,
    String market = 'IN',
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      final song = await _musicService.playFromArtist(
        artistId: artistId,
        market: market,
      );

      await _playSong(song);
      
      debugPrint('[MusicProvider] ✅ Playing from artist: ${song.title}');
    } catch (e) {
      debugPrint('[MusicProvider] ❌ Play from artist failed: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // ============================================================================
  // PLAYBACK CONTROLS
  // ============================================================================

  /// Play or resume
  Future<void> play() async {
    if (_currentSong == null) return;
    
    try {
      await _audioPlayer.play();
      debugPrint('[MusicProvider] ▶️ Playing');
    } catch (e) {
      debugPrint('[MusicProvider] ❌ Play failed: $e');
    }
  }

  /// Pause
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      debugPrint('[MusicProvider] ⏸️ Paused');
    } catch (e) {
      debugPrint('[MusicProvider] ❌ Pause failed: $e');
    }
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Stop
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _currentSong = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      notifyListeners();
      debugPrint('[MusicProvider] ⏹️ Stopped');
    } catch (e) {
      debugPrint('[MusicProvider] ❌ Stop failed: $e');
    }
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);
      debugPrint('[MusicProvider] ⏩ Seeked to ${position.inSeconds}s');
    } catch (e) {
      debugPrint('[MusicProvider] ❌ Seek failed: $e');
    }
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    try {
      _volume = volume.clamp(0.0, 1.0);
      await _audioPlayer.setVolume(_volume);
      notifyListeners();
      debugPrint('[MusicProvider] 🔊 Volume: ${(_volume * 100).toInt()}%');
    } catch (e) {
      debugPrint('[MusicProvider] ❌ Set volume failed: $e');
    }
  }

  // ============================================================================
  // QUEUE NAVIGATION
  // ============================================================================

  /// Play next track
  Future<void> next() async {
    final nextSong = await queueManager.next();
    if (nextSong != null) {
      await _playSong(nextSong);
    }
  }

  /// Play previous track
  Future<void> previous() async {
    // If more than 3 seconds into the song, restart it
    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    final previousSong = queueManager.previous();
    if (previousSong != null) {
      await _playSong(previousSong);
    }
  }

  /// Jump to specific track in queue
  Future<void> jumpToTrack(int index) async {
    final song = queueManager.jumpTo(index);
    if (song != null) {
      await _playSong(song);
    }
  }

  // ============================================================================
  // SHUFFLE & REPEAT
  // ============================================================================

  void toggleShuffle() {
    queueManager.toggleShuffle();
    notifyListeners();
  }

  void cycleRepeatMode() {
    queueManager.cycleRepeatMode();
    notifyListeners();
  }

  void setRepeatMode(RepeatMode mode) {
    queueManager.setRepeatMode(mode);
    notifyListeners();
  }

  // ============================================================================
  // QUEUE MANIPULATION
  // ============================================================================

  void addNext(Song song) {
    queueManager.addNext(song);
  }

  void addToEnd(Song song) {
    queueManager.addToEnd(song);
  }

  void removeFromQueue(int index) {
    queueManager.remove(index);
  }

  void moveInQueue(int from, int to) {
    queueManager.move(from, to);
  }

  void clearQueue() {
    queueManager.clear();
    stop();
  }

  // ============================================================================
  // INTERNAL METHODS
  // ============================================================================

  Future<void> _playSong(Song song) async {
    try {
      _currentSong = song;
      _isLoading = true;
      notifyListeners();

      if (song.previewUrl == null || song.previewUrl!.isEmpty) {
        throw Exception('No preview URL available for ${song.title}');
      }

      await _audioPlayer.setUrl(song.previewUrl!);
      await _audioPlayer.play();

      _isLoading = false;
      notifyListeners();

      debugPrint('[MusicProvider] 🎵 Now playing: ${song.title} by ${song.artist}');
    } catch (e) {
      debugPrint('[MusicProvider] ❌ Failed to play song: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  void _onSongCompleted() {
    debugPrint('[MusicProvider] ✅ Song completed: ${_currentSong?.title}');

    // Track completion for ML engine (JioSaavn only)
    if (_currentSong != null && _musicService.activeProvider == MusicServiceProvider.jiosaavn) {
      final completionRate = _duration.inMilliseconds > 0
          ? _position.inMilliseconds / _duration.inMilliseconds
          : 1.0;
      _musicService.trackSongPlay(_currentSong!, completionRate: completionRate);
    }

    // Auto-play next
    next();
  }

  // ============================================================================
  // PROVIDER MANAGEMENT
  // ============================================================================

  void activateSpotify(String accessToken, {Duration expiresIn = const Duration(hours: 1)}) {
    _musicService.activateSpotify(accessToken, expiresIn: expiresIn);
    notifyListeners();
  }

  void activateJioSaavn() {
    _musicService.activateJioSaavn();
    notifyListeners();
  }

  // ============================================================================
  // SEARCH
  // ============================================================================

  Future<UnifiedSearchResults> search(String query, {int limit = 20}) async {
    return await _musicService.search(query, limit: limit);
  }

  // ============================================================================
  // DEBUG
  // ============================================================================

  void printQueue() {
    queueManager.printQueue();
  }

  Map<String, dynamic> getDebugInfo() {
    return {
      'currentSong': _currentSong?.title,
      'isPlaying': _isPlaying,
      'isLoading': _isLoading,
      'position': _position.toString(),
      'duration': _duration.toString(),
      'progress': '${(progress * 100).toStringAsFixed(1)}%',
      'volume': '${(_volume * 100).toInt()}%',
      'queueLength': _queue.length,
      'currentIndex': _currentIndex,
      ..._musicService.getProviderInfo(),
    };
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _queueSubscription?.cancel();
    _indexSubscription?.cancel();
    _audioPlayer.dispose();
    _musicService.dispose();
    super.dispose();
  }
}
