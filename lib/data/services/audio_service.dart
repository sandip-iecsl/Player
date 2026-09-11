import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../domain/entities/song.dart';
import 'ml_recommendation_engine.dart';
import 'hybrid_search_service.dart';
import 'local_taste_engine.dart';
import 'global_firebase_engine.dart';
import 'offline_storage_service.dart';
import 'linguistic_engine.dart';
import 'direct_jiosaavn_service.dart';
import 'youtube_extractor_service.dart';

late AudioServiceHandler audioHandler;

// ─────────────────────────────────────────────────────────────────────────────
// Playback Context
// Defines WHERE a queue was loaded from, gating autoplay / shuffle / repeat.
// ─────────────────────────────────────────────────────────────────────────────
enum PlaybackContext {
  /// Tracks from a specific album — shuffle within album only, no autoplay.
  album,

  /// Tracks from a user-created or app playlist — shuffle within playlist.
  playlist,

  /// User tapped a song from search results — autoplay radio fires after queue ends.
  search,

  /// Algorithm / radio seed — infinite autoplay always on.
  radio,

  /// Local device files — no autoplay, no internet algorithm.
  local,
}

class AudioServiceHandler extends BaseAudioHandler {
  // Non-final so we can dispose + recreate when ExoPlayer gets a stuck player ID
  late AudioPlayer _audioPlayer;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));
  
  // ML Recommendation Engine
  final MLRecommendationEngine _mlEngine = MLRecommendationEngine();
  final LinguisticEngine _linguisticEngine = LinguisticEngine();
  
  // Anti-spam debounce session tracking
  int _playSessionId = 0;
  Timer? _skipDebounceTimer;

  // Mutex: prevents concurrent _playSong calls from crashing ExoPlayer
  bool _isPlayingSong = false;

  // Class-level completion guard (was incorrectly a closure-local, causing duplicate _onTrackEnded on listener re-creation)
  bool _hasFiredCompletion = false;

  // Subscription handles — stored so _resetPlayer can cancel them before re-attaching
  StreamSubscription? _playbackEventSub;
  StreamSubscription? _positionSub1;
  StreamSubscription? _positionSub2;
  StreamSubscription? _playerDurSub;
  StreamSubscription? _processingStateSub;
  StreamSubscription? _uiPositionSourceSub;
  Timer? _uiPositionTimer;
  Duration? _pendingUiPosition;
  final _uiPositionController = StreamController<Duration>.broadcast();
  final Map<String, String> _warmedStreamUrls = {};

  // Consecutive failure counter — resets on any successful play
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 15;
  
  // Hybrid Search Service for Spotify recommendations fallback
  final HybridSearchService _hybridSearch = HybridSearchService();

  // Direct JioSaavn Service — used to refresh expired CDN stream URLs
  final DirectJioSaavnService _directService = DirectJioSaavnService();

  // YouTube Extractor Service — used to extract links and refresh YouTube streams
  final YouTubeExtractorService _ytExtractor = YouTubeExtractorService();
  
  // Local Taste Matrix Engine
  final LocalTasteEngine _tasteEngine = LocalTasteEngine();
  
  // Global Firebase Engine
  final GlobalFirebaseEngine _globalEngine = GlobalFirebaseEngine();

  // ── Queue state ───────────────────────────────────────────────────────────
  /// The currently active playback queue (may be shuffled).
  final List<Song> _queue = [];

  /// Global play history to prevent duplicate tracks over long listening sessions
  final List<Song> _playHistory = [];

  /// Preserves the original, un-shuffled order so shuffle can be reversed.
  final List<Song> _originalQueue = [];

  int _currentIndex = 0;

  /// Loaded context — determines end-of-queue behaviour.
  PlaybackContext _context = PlaybackContext.radio;
  String? _contextId;

  PlaybackContext get currentContext => _context;
  String? get currentContextId => _contextId;

  /// Kept for external callers that still reference isAlgorithmEnabled.
  /// Internally, context drives the decision.
  bool get isAlgorithmEnabled =>
      _context == PlaybackContext.search || _context == PlaybackContext.radio;

  /// True when the queue was loaded from local device storage.
  bool get _isLocalQueue => _context == PlaybackContext.local;

  Timer? _sleepTimer;
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;
  AudioServiceRepeatMode  _repeatMode  = AudioServiceRepeatMode.none;

  // Stream that emits the full Song object (with previewUrl) on every song change
  final _currentSongController = StreamController<Song?>.broadcast();
  Stream<Song?> get currentSongStream => _currentSongController.stream;

  Song? _currentSong;

  // ── Volume & Audio Boost State ──────────────────────────────────────────
  double _volumeMultiplier = 1.0;
  double _maxVolumeLimit = 2.0; // Configurable max volume limit
  final _volumeController = StreamController<double>.broadcast();

  double get volumeMultiplier => _volumeMultiplier;
  double get maxVolumeLimit => _maxVolumeLimit;
  Stream<double> get volumeStream => _volumeController.stream;

  // ── EQ State ────────────────────────────────────────────────────────────
  double _bassGain = 0.0; // 0.0 to 1.0
  double _trebleGain = 0.0; // 0.0 to 1.0
  AndroidEqualizer? _equalizer;

  double get bassGain => _bassGain;
  double get trebleGain => _trebleGain;

  void setMaxVolumeLimit(double limit) {
    _maxVolumeLimit = limit;
    if (_volumeMultiplier > _maxVolumeLimit) {
      setVolume(_maxVolumeLimit);
    }
  }

  void setBassGain(double gain) {
    _bassGain = gain.clamp(0.0, 1.0);
    _updateEqualizer();
  }

  void setTrebleGain(double gain) {
    _trebleGain = gain.clamp(0.0, 1.0);
    _updateEqualizer();
  }

  Future<void> _updateEqualizer() async {
    if (_equalizer == null) return;
    try {
      final parameters = await _equalizer!.parameters;
      final max = parameters.maxDecibels;
      if (parameters.bands.isNotEmpty) {
         // Bass is band 0
         parameters.bands.first.setGain(_bassGain * max);
         // Treble is last band
         parameters.bands.last.setGain(_trebleGain * max);
      }
      _equalizer!.setEnabled(_bassGain > 0 || _trebleGain > 0);
      print('[Audio] 🎛️ Equalizer updated: Bass=$_bassGain, Treble=$_trebleGain');
    } catch (e) {
      print('[Audio] ❌ Failed to update equalizer: $e');
    }
  }

  /// Sets volume directly (clamped 0.0 to _maxVolumeLimit)
  Future<void> setVolume(double volume) async {
    _volumeMultiplier = volume.clamp(0.0, _maxVolumeLimit);
    await _audioPlayer.setVolume(_volumeMultiplier);
    _volumeController.add(_volumeMultiplier);
  }

  /// Smoothly transitions the volume to enable or disable boost
  Future<void> toggleBoost() async {
    final bool isBoosted = _volumeMultiplier > 1.0;
    final double target = isBoosted ? 1.0 : _maxVolumeLimit;
    
    // Smooth transition over 400ms
    final double start = _volumeMultiplier;
    const int steps = 20;
    final double stepVal = (target - start) / steps;
    
    for (int i = 1; i <= steps; i++) {
      _volumeMultiplier = start + (stepVal * i);
      await _audioPlayer.setVolume(_volumeMultiplier);
      _volumeController.add(_volumeMultiplier);
      await Future.delayed(const Duration(milliseconds: 20));
    }
    _volumeMultiplier = target;
    await _audioPlayer.setVolume(_volumeMultiplier);
    _volumeController.add(_volumeMultiplier);
    print('[Audio] 🔊 Boost toggled. Volume updated to ${(_volumeMultiplier * 100).toInt()}%');
  }

  void _initAudioPlayer() {
    try {
      if (Platform.isAndroid) {
        _equalizer = AndroidEqualizer();
        _audioPlayer = AudioPlayer(
          audioPipeline: AudioPipeline(androidAudioEffects: [_equalizer!])
        );
      } else {
        _audioPlayer = AudioPlayer();
      }
    } catch (e) {
      print('[Audio] ❌ Failed to init audio player with effects, falling back: $e');
      _audioPlayer = AudioPlayer();
    }
  }

  AudioServiceHandler() {
    _initAudioPlayer();
    _tasteEngine.init();
    _setupPlayerListeners();
    _setupConnectivityListener();
  }

  /// Dispose the broken AudioPlayer and create a FRESH instance.
  /// Called when ExoPlayer gets stuck with a stale native player ID.
  /// CRITICAL: Simply calling stop() is NOT enough — the stuck native player
  /// stays alive and any subsequent setUrl() call throws an unrecoverable
  /// native exception. We must dispose + recreate the Dart + native handle.
  Future<void> _resetPlayer() async {
    print('[Audio] 🔄 Resetting AudioPlayer — disposing broken instance...');

    // 1. Cancel all stream subscriptions before disposing
    _playbackEventSub?.cancel();
    _positionSub1?.cancel();
    _positionSub2?.cancel();
    _playerDurSub?.cancel();
    _processingStateSub?.cancel();
    _uiPositionSourceSub?.cancel();
    _uiPositionTimer?.cancel();
    _playbackEventSub = null;
    _positionSub1 = null;
    _positionSub2 = null;
    _playerDurSub = null;
    _processingStateSub = null;

    // 2. Attempt graceful stop on the old instance before dispose
    try {
      await _audioPlayer.stop().timeout(
        const Duration(milliseconds: 300),
        onTimeout: () {
          print('[Audio] ⚠️ Stop timeout during reset, proceeding to dispose');
        },
      );
    } catch (_) {}

    // 3. Dispose the broken native player completely
    try {
      await _audioPlayer.dispose();
    } catch (_) {}

    // 4. Allow Android to release the native ExoPlayer handle
    await Future.delayed(const Duration(milliseconds: 200));

    // 5. Create a brand-new AudioPlayer instance (fresh native player)
    _initAudioPlayer();

    // 6. Re-attach all stream listeners on the new player
    _setupPlayerListeners();

    _consecutiveFailures = 0;
    _hasFiredCompletion = false;

    // 7. Restore equalizer settings on the new instance
    if (_bassGain > 0 || _trebleGain > 0) _updateEqualizer();

    print('[Audio] ✅ AudioPlayer fully reset — new native instance ready');
  }

  void _setupConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
      final isOffline = results.contains(ConnectivityResult.none);
      if (isOffline) {
        if (_context != PlaybackContext.local) {
          print('[Audio] 📴 Network dropped. Switching queue to local-only resiliency mode.');
          _context = PlaybackContext.local;
          _contextId = 'offline_resiliency';
          // Dynamically filter active queue for downloaded tracks
          final offlineSongs = OfflineStorageService.getOfflineSongs();
          final offlineIds = offlineSongs.map((s) => s.id).toSet();
          
          final localOnlyQueue = _queue.where((s) => 
            offlineIds.contains(s.id) || (s.previewUrl != null && !s.previewUrl!.startsWith('http'))
          ).toList();
          
          if (localOnlyQueue.isNotEmpty) {
            _queue.clear();
            _queue.addAll(localOnlyQueue);
            _originalQueue.clear();
            _originalQueue.addAll(localOnlyQueue);
            
            // Adjust current index to keep playing if current track is local, else skip to first local
            int newIdx = _queue.indexWhere((s) => s.id == _currentSong?.id);
            _currentIndex = newIdx >= 0 ? newIdx : 0;
            if (newIdx < 0) _playSong(_queue[_currentIndex]);
          } else {
            stop();
            print('[Audio] ⚠️ No local tracks available to play offline.');
          }
        }
      } else {
        print('[Audio] 📶 Network restored. Running offline sync transactions...');
        await _globalEngine.syncOfflineQueue();
      }
    });
  }

  @override
  Future<void> onTaskRemoved() async {
    print('[Audio] 🧹 App closed. Stopping background service...');
    await stop();
    await super.onTaskRemoved();
  }

  void _setupPlayerListeners() {
    // CRITICAL: cancel existing subs before re-attaching.
    // _resetPlayer() calls this again on a new AudioPlayer instance.
    // Without this, listeners stack up and _onTrackEnded fires multiple times per song.
    _playbackEventSub?.cancel();
    _positionSub1?.cancel();
    _positionSub2?.cancel();
    _playerDurSub?.cancel();
    _processingStateSub?.cancel();
    _hasFiredCompletion = false;
    // Cancel existing subscriptions BEFORE re-subscribing.
    // _resetPlayer() calls this again on a brand-new AudioPlayer instance.
    // Without cancellation, listeners accumulate and _onTrackEnded fires 2-4x per song.
    // ── Enhanced Playback state mirror with system notification media controls ───────────
    _playbackEventSub = _audioPlayer.playbackEventStream.listen((event) {
      final isPlaying = _audioPlayer.playing;
      final processingState = _audioPlayer.processingState;
      
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
          MediaAction.setRating,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.stop,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.fastForward,
          MediaAction.rewind,
        },
        processingState: const {
          ProcessingState.idle:      AudioProcessingState.idle,
          ProcessingState.loading:   AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready:     AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[processingState]!,
        playing:          isPlaying,
        updatePosition:   _audioPlayer.position,
        bufferedPosition: _audioPlayer.bufferedPosition,
        speed:            _audioPlayer.speed,
        queueIndex:       _currentIndex,
        shuffleMode:      _shuffleMode,
        repeatMode:       _repeatMode,
        // Android System Media Notification: 0=Previous, 1=Play/Pause, 2=Next
        androidCompactActionIndices: const [0, 1, 2],
      ));
    });

    // Also listen to position stream for smooth seek bar updates on lockscreen
    _positionSub1 = _audioPlayer.positionStream.listen((position) {
      if (!playbackState.hasValue) return;
      playbackState.add(playbackState.value.copyWith(
        updatePosition: position,
      ));
    });



    // ── Track-ended gatekeeper ───────────────────────────────────────────────
    // Evaluated in strict priority order:
    //  Gate 1 ▶ Repeat One  — LoopMode.one handles it inside just_audio; never fires here.
    //  Gate 2 ▶ Next track  — advance index sequentially (shuffled order if shuffle ON).
    //  Gate 3 ▶ Repeat All  — wrap back to index 0.
    //  Gate 4 ▶ Autoplay    — only for search / radio contexts.
    //  Gate 5 ▶ Stop        — clean stop for album / playlist / local.
    _processingStateSub = _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_hasFiredCompletion) {
        _hasFiredCompletion = true;
        // Track song completion for ML engine
        // Use _currentSong field or fall back to queue getter
        final songToLog = _currentSong ?? currentSong;
        if (songToLog != null) {
          final completionRate = _audioPlayer.position.inSeconds /
                                (songToLog.duration.inSeconds > 0 ? songToLog.duration.inSeconds : 1);
          _mlEngine.trackSongPlay(songToLog, completionRate: completionRate.clamp(0.0, 1.0));
          print('[ML] 📊 Tracked: ${songToLog.title} - Completion: ${(completionRate * 100).toStringAsFixed(1)}%');

          // Log track playback to Local Hive history + cloud backup
          _tasteEngine.logPlay(songToLog);
          // Log to Global Firestore play count
          _globalEngine.logPlay(songToLog);
        }
        _onTrackEnded();
      }
    });

    // Position is native-clock data, but rebuilding the entire UI for every
    // native tick is unnecessary. Publish at most 10 updates per second for
    // widgets; lock-screen playbackState still receives every native update.
    _uiPositionSourceSub = _audioPlayer.positionStream.listen((position) {
      _pendingUiPosition = position;
      if (_uiPositionTimer != null) return;
      _uiPositionTimer = Timer(const Duration(milliseconds: 100), () {
        _uiPositionTimer = null;
        final pendingPosition = _pendingUiPosition;
        if (pendingPosition != null && !_uiPositionController.isClosed) {
          _uiPositionController.add(pendingPosition);
        }
      });
    });

    // Fallback for Android ExoPlayer quirk where it sometimes hangs at the end
    // of an MP4/M4A stream and never emits ProcessingState.completed
    _positionSub2 = _audioPlayer.positionStream.listen((pos) {
      final dur = _audioPlayer.duration;
      if (dur != null && dur.inMilliseconds > 0) {
        // If position is at the very start (e.g. new song), reset the fired flag
        if (pos.inMilliseconds < 1000) {
          _hasFiredCompletion = false;
        }
        // If we reach within 300ms of the end, artificially trigger completion
        else if (pos.inMilliseconds >= dur.inMilliseconds - 300 && !_hasFiredCompletion) {
          print('[Audio] ⚠️ positionStream fallback reached end of track. Triggering completion.');
          _hasFiredCompletion = true;
          
          final songToLog = _currentSong ?? currentSong;
          if (songToLog != null) {
            _mlEngine.trackSongPlay(songToLog, completionRate: 1.0);
            _tasteEngine.logPlay(songToLog);
            _globalEngine.logPlay(songToLog);
          }
          _onTrackEnded();
        }
      }
    });


  }

  /// Safely fetch a song from the active queue with index and bounds validation.
  Song? _getSafeQueueSong(int index) {
    if (_queue.isEmpty || index < 0 || index >= _queue.length) {
      print('[Audio] ⚠️ Invalid queue access: index=$index, length=${_queue.length}');
      return null;
    }
    return _queue[index];
  }

  // ── onTrackEnded — the single structural gatekeeper ─────────────────────────
  void _onTrackEnded() {
    print('[Audio] 🏁 Track ended - Current index: $_currentIndex, Queue length: ${_queue.length}');

    if (_queue.isEmpty) {
      print('[Audio] ⚠️ Track ended but queue is empty');
      _audioPlayer.stop();
      return;
    }

    // Step 1: Check Repeat One Gate
    if (_repeatMode == AudioServiceRepeatMode.one) {
      print('[Audio] 🔁 Repeat ONE - Replaying current track');
      seek(Duration.zero);
      play();
      return;
    }

    // Step 2: Check Active Queue Boundaries
    if (_currentIndex < _queue.length - 1) {
      print('[Audio] ➡️ Moving to next song in queue');
      _currentIndex++;
      final nextSong = _getSafeQueueSong(_currentIndex);
      if (nextSong != null) {
        _currentSongController.add(nextSong);
        _playSong(nextSong);
      } else {
        print('[Audio] ⚠️ Next song is null, stopping');
        _audioPlayer.stop();
      }
      return;
    }

    // Step 3: Check Repeat All Gate
    if (_repeatMode == AudioServiceRepeatMode.all) {
      print('[Audio] 🔁 Repeat ALL - Wrapping to start');
      _currentIndex = 0;
      final firstSong = _getSafeQueueSong(_currentIndex);
      if (firstSong != null) {
        _currentSongController.add(firstSong);
        _playSong(firstSong);
      } else {
        _audioPlayer.stop();
      }
      return;
    }

    // Step 4: Execute Infinite Autoplay Fallback (Only for radio/search context)
    if (_context == PlaybackContext.album || _context == PlaybackContext.playlist || _context == PlaybackContext.local) {
      print('[Audio] ⏹ Playlist/Album/Local queue completed. End of queue reached.');
      _audioPlayer.stop();
      return;
    }

    if (_context == PlaybackContext.search || _context == PlaybackContext.radio) {
      print('[Audio] 🤖 Radio/Search ended - Generating next recommendations');
      _playNextAlgorithmSong();
      return;
    }

    print('[Audio] ⏹ End of queue [${_context.name}] — stopped.');
    _audioPlayer.stop();
  }

  // ── Queue loaders ────────────────────────────────────────────────────────

  bool _isTrendingVersion(Map<String, dynamic> r) {
    final t = '${r['name'] ?? ''} ${r['album']?['name'] ?? ''}'.toLowerCase();
    return t.contains('trending version') ||
        t.contains('trending remake') ||
        t.contains('speed up') ||
        t.contains('sped up') ||
        t.contains('slowed reverb') ||
        t.contains('lofi version') ||
        t.contains('short version');
  }

  bool _isDuplicateSong(Song newSong) {
    if (_queue.any((q) => q.id == newSong.id)) return true;
    if (_playHistory.any((q) => q.id == newSong.id)) return true;
    
    // Fallback: title + artist fuzzy match to catch exact same songs with different IDs
    final newTitle = newSong.title.replaceAll(RegExp(r'[\(\[\-\|].*'), '').trim().toLowerCase();
    final newArtist = newSong.artist.split(',').first.trim().toLowerCase();
    
    // Combine queue and history for duplicate scanning
    final memoryPool = [..._queue, ..._playHistory];
    
    return memoryPool.any((q) {
      final existingTitle = q.title.replaceAll(RegExp(r'[\(\[\-\|].*'), '').trim().toLowerCase();
      final existingArtist = q.artist.split(',').first.trim().toLowerCase();
      
      // If both cleaned title and cleaned primary artist are extremely similar, consider it a duplicate
      if (newTitle.isNotEmpty && existingTitle.isNotEmpty && newArtist.isNotEmpty && existingArtist.isNotEmpty) {
        bool titleMatch = newTitle == existingTitle || newTitle.contains(existingTitle) || existingTitle.contains(newTitle);
        bool artistMatch = newArtist == existingArtist || newArtist.contains(existingArtist) || existingArtist.contains(newArtist);
        return titleMatch && artistMatch;
      }
      return false;
    });
  }

  Future<void> _fetchAndAppendAlgorithmSongs(Song seedSong) async {
    const apiBase = 'https://jiosaavn-api-peach.vercel.app/api';
    try {
      final primaryArtist = seedSong.artist.split(',').first.trim();
      // Search for the artist to create an "Artist Radio" experience
      final query = primaryArtist;
      final response = await _dio.get(
        '$apiBase/search/songs',
        queryParameters: {'query': query, 'limit': 40, 'page': 1},
      );
      if (response.data?['success'] == true) {
        final results = response.data['data']?['results'] as List? ?? [];
        final newSongs = results
            .whereType<Map<String, dynamic>>()
            .where((r) => !_isTrendingVersion(r))
            .map((r) => _parseSong(r))
            .where((s) => s.previewUrl != null && s.previewUrl!.isNotEmpty)
            .where((s) => !_isDuplicateSong(s))
            .toList();
        if (newSongs.isNotEmpty) {
          _queue.addAll(newSongs);
          _originalQueue.addAll(newSongs);
          print('[Algorithm] ✅ Appended ${newSongs.length} similar tracks upfront for SEARCH context.');
        }
      }
    } catch (_) {}
  }

  /// Loads and immediately plays a queue.
  /// [context] determines end-of-queue behaviour (see [PlaybackContext]).
  Future<void> loadQueue(
    List<Song> songs, {
    int startIndex = 0,
    PlaybackContext context = PlaybackContext.radio,
    String? contextId,
  }) async {
    if (songs.isEmpty) return;
    _context = _inferContext(songs, context);

    // Spotify/JioSaavn Auto-Shuffle Logic
    // If playing from Search or Radio, auto-enable shuffle.
    // If playing from Playlist, Album, or Local, auto-disable shuffle.
    if (_context == PlaybackContext.search || _context == PlaybackContext.radio) {
      _shuffleMode = AudioServiceShuffleMode.all;
    } else {
      _shuffleMode = AudioServiceShuffleMode.none;
    }
    playbackState.add(playbackState.value.copyWith(shuffleMode: _shuffleMode));

    _queue
      ..clear()
      ..addAll(songs);
    _originalQueue
      ..clear()
      ..addAll(songs);
    
    // Apply shuffle if it's already enabled
    if (_shuffleMode == AudioServiceShuffleMode.all) {
      print('[Audio] 🔀 Auto-Shuffle is ON for ${_context.name} context');
      final currentSong = songs[startIndex];
      
      // Fisher-Yates shuffle
      final shuffled = List<Song>.from(_queue);
      final rng = Random();
      for (int i = shuffled.length - 1; i > 0; i--) {
        final j = rng.nextInt(i + 1);
        final temp = shuffled[i];
        shuffled[i] = shuffled[j];
        shuffled[j] = temp;
      }
      
      // Place the starting song first
      shuffled.remove(currentSong);
      shuffled.insert(0, currentSong);
      
      _queue
        ..clear()
        ..addAll(shuffled);
      _currentIndex = 0;
    } else {
      _currentIndex = startIndex.clamp(0, songs.length - 1);
    }
    
    _contextId = contextId;
    print('[Audio] 📂 Queue loaded [${_context.name}] (contextId: $_contextId) '
        '${songs.length} tracks, starting at $_currentIndex (shuffle: ${_shuffleMode == AudioServiceShuffleMode.all})');
    await _playSong(_queue[_currentIndex]);
    unawaited(_warmAdjacentStreams());

    // FLOW 1: Trigger recommendation engine to fetch similar tracks upfront
    if (_context == PlaybackContext.search) {
      _fetchAndAppendAlgorithmSongs(_queue[_currentIndex]);
    }
  }

  /// Appends songs to the active queue and original queue dynamically.
  void appendSongs(List<Song> songs) {
    if (songs.isEmpty) return;
    
    // Add unique songs to avoid duplicate entries in the same queue
    final newSongs = songs.where((s) => !_queue.any((q) => q.id == s.id)).toList();
    if (newSongs.isEmpty) return;

    _queue.addAll(newSongs);
    _originalQueue.addAll(newSongs);
    print('[Audio] ➕ Appended ${newSongs.length} tracks dynamically to current queue. Total now: ${_queue.length}');
  }

  Future<void> _warmAdjacentStreams() async {
    if (_queue.length < 2) return;
    final indexes = <int>{_currentIndex - 1, _currentIndex + 1}
        .where((index) => index >= 0 && index < _queue.length);
    for (final index in indexes) {
      final song = _queue[index];
      final isYouTube = song.isYoutubeImport || song.id.startsWith('yt_') || song.youtubeUrl != null;
      if (!isYouTube || _warmedStreamUrls.containsKey(song.id)) continue;
      try {
        final url = await _ytExtractor.getFreshStreamUrl(song);
        if (url != null && url.isNotEmpty) {
          _warmedStreamUrls[song.id] = url;
        }
      } catch (error) {
        print('[Audio] ⚠️ Adjacent stream warmup failed for ${song.id}: $error');
      }
    }
  }

  /// Infers context from URL type when not explicitly given.
  PlaybackContext _inferContext(List<Song> songs, PlaybackContext hint) {
    if (hint != PlaybackContext.radio) return hint; // explicit always wins
    final url = songs.first.previewUrl ?? '';
    if (!url.startsWith('http')) return PlaybackContext.local;
    return hint;
  }


  /// Load queue, seek to position, but stay PAUSED — used by sync guest
  Future<void> loadQueuePaused(List<Song> songs,
      {int startIndex = 0, Duration seekTo = Duration.zero}) async {
    _queue.clear();
    _queue.addAll(songs);
    _originalQueue
      ..clear()
      ..addAll(songs);
    _currentIndex = startIndex.clamp(0, songs.length - 1);
    await _playSongPaused(_queue[_currentIndex], seekTo: seekTo);
  }

  /// Ultra-fast loading for instant sync - zero delays
  Future<void> loadQueueInstant(List<Song> songs,
      {int startIndex = 0, Duration seekTo = Duration.zero}) async {
    _queue.clear();
    _queue.addAll(songs);
    _originalQueue
      ..clear()
      ..addAll(songs);
    _currentIndex = startIndex.clamp(0, songs.length - 1);
    await _playSongInstant(_queue[_currentIndex], seekTo: seekTo);
  }

  /// Ultra-fast song loading for instant sync - absolute minimal delays
  Future<void> _playSongInstant(Song song, {Duration seekTo = Duration.zero}) async {
    try {
      print('[Audio] ⚡ INSTANT loading: "${song.title}" seeking to ${seekTo.inSeconds}s');
      _currentSong = song;          // ← track for completion/transition logging
      _currentSongController.add(song);
      mediaItem.add(MediaItem(
        id: song.id, title: song.title, artist: song.artist,
        album: song.album,
        artUri: song.albumArt != null ? Uri.tryParse(song.albumArt!) : null,
        duration: song.duration,
        extras: {
          'enhancedNotification': true,
          'beatResponseEnabled': true,
          'customStyle': 'enhanced',
          'albumArt': song.albumArt,
          'previewUrl': song.previewUrl,
        },
      ));
      
      // ZERO-DELAY approach - direct loading without any cleanup or waiting
      final url = OfflineStorageService.getLocalPath(song.id) ?? song.previewUrl;
      if (url != null && url.isNotEmpty) {
        if (!url.startsWith('http')) {
          // Local file - instant
          await _audioPlayer.setAudioSource(AudioSource.uri(Uri.file(url)));
        } else {
          // Network stream - no buffering wait, direct loading
          await _audioPlayer.setUrl(url); // Use direct setUrl for fastest loading
        }
        
        // INSTANT seek - no waiting, no delays
        if (seekTo > Duration.zero) {
          _audioPlayer.seek(seekTo); // Don't await - fire and forget for speed
        }
        
        print('[Audio] ⚡ INSTANT load complete at ${seekTo.inSeconds}s - ZERO DELAY');
      }
    } catch (e) {
      print('[Audio] ❌ Instant load error: $e');
      // Fallback to basic loading
      try {
        final url = OfflineStorageService.getLocalPath(song.id) ?? song.previewUrl;
        if (url != null && url.isNotEmpty) {
          await _audioPlayer.setUrl(url);
          if (seekTo > Duration.zero) {
            _audioPlayer.seek(seekTo);
          }
        }
      } catch (_) {}
    }
  }

  /// Load song, buffer it, seek to position — but do NOT play. Used for sync.
  Future<void> _playSongPaused(Song song, {Duration seekTo = Duration.zero}) async {
    try {
      print('[Audio] 🔄 Loading paused: "${song.title}" seeking to ${seekTo.inSeconds}s');
      _currentSong = song;          // ← track for completion/transition logging
      _currentSongController.add(song);
      mediaItem.add(MediaItem(
        id: song.id, title: song.title, artist: song.artist,
        album: song.album,
        artUri: song.albumArt != null ? Uri.tryParse(song.albumArt!) : null,
        duration: song.duration,
        extras: {
          'enhancedNotification': true,
          'beatResponseEnabled': true,
          'customStyle': 'enhanced',
          'albumArt': song.albumArt,
          'previewUrl': song.previewUrl,
        },
      ));
      
      // Ultra-fast cleanup for sync - minimal delays
      await _audioPlayer.stop();
      
      final url = OfflineStorageService.getLocalPath(song.id) ?? song.previewUrl;
      if (url != null && url.isNotEmpty) {
        if (!url.startsWith('http')) {
          // Local file - instant loading
          await _audioPlayer.setAudioSource(AudioSource.uri(Uri.file(url)));
          await _audioPlayer.load();
        } else {
          try {
            // Network stream - optimized for sync
            await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(url)));
            await _audioPlayer.load();
            
            // Minimal buffering for sync - prioritize speed over buffer
            int retries = 0;
            while (retries < 3 && _audioPlayer.processingState == ProcessingState.loading) {
              await Future.delayed(const Duration(milliseconds: 25));
              retries++;
            }
          } catch (_) {
            await _audioPlayer.setUrl(url);
            await _audioPlayer.load();
          }
        }
        
        // Seek immediately after loading
        if (seekTo > Duration.zero) {
          await _audioPlayer.seek(seekTo);
        }
        
        print('[Audio] ✅ Loaded paused at ${seekTo.inSeconds}s, ready for sync play');
      }
    } catch (e) {
      print('[Audio] ❌ loadPaused error: $e');
    }
  }

  Future<void> _playSong(Song song) async {
    final int currentSession = ++_playSessionId;
    int waitCount = 0;
    const maxWait = 50;
    while (_isPlayingSong && waitCount < maxWait) {
      await Future.delayed(const Duration(milliseconds: 25));
      waitCount++;
      if (_playSessionId != currentSession) {
        print('[Audio] ℹ️ Play session cancelled while waiting for mutex');
        return;
      }
    }

    if (_isPlayingSong && waitCount >= maxWait) {
      print('[Audio] ⚠️ Mutex timeout exceeded, forcing release');
      _isPlayingSong = false;
    }

    if (_playSessionId != currentSession) return;
    _isPlayingSong = true;
    _hasFiredCompletion = false;
    try {
      if (song.id.isEmpty) {
        throw Exception('Invalid song: empty ID');
      }

      print('[Audio] 🎵 ── Loading: "${song.title}" by ${song.artist} ──');

      // Log transition for Metric D (Co-Occurrence Transition Matrix)
      if (_currentSong != null && _currentSong!.id != song.id) {
        _tasteEngine.logTransition(_currentSong!, song);
        _globalEngine.logTransition(_currentSong!, song);
      }

      _currentSong = song;

      _playHistory.add(song);
      if (_playHistory.length > 50) {
        _playHistory.removeAt(0);
      }

      _currentSongController.add(song);

      if (_context == PlaybackContext.radio || _context == PlaybackContext.search) {
        _prepareNextAlgorithmSong();
      }

      mediaItem.add(MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        artUri: song.albumArt != null ? Uri.tryParse(song.albumArt!) : null,
        duration: song.duration,
        extras: {
          'enhancedNotification': true,
          'beatResponseEnabled': true,
          'customStyle': 'enhanced',
          'albumArt': song.albumArt,
          'previewUrl': song.previewUrl,
        },
      ));

      print('[Audio] ⏹ Stopping previous player instance before new source...');
      try {
        await _audioPlayer.stop().timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {
            print('[Audio] ⚠️ Stop timeout, continuing with source set');
          },
        );
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        print('[Audio] ⚠️ Stop error (continuing): $e');
      }
      if (_playSessionId != currentSession) {
        print('[Audio] ℹ️ Session changed during cleanup, aborting');
        return;
      }

        String? audioUrl = OfflineStorageService.getLocalPath(song.id) ??
          _warmedStreamUrls[song.id] ?? song.previewUrl;

      // Dynamically fetch missing or unstreamable URL
      if ((audioUrl == null || audioUrl.isEmpty || audioUrl.startsWith('unstreamable')) && song.id.isNotEmpty) {
        if (song.isYoutubeImport || song.id.startsWith('yt_') || song.youtubeUrl != null) {
          print('[Audio] 🎬 Extracting YouTube stream URL for "${song.title}"...');
          try {
            final ytFreshUrl = await _ytExtractor.getFreshStreamUrl(song);
            if (ytFreshUrl != null && ytFreshUrl.isNotEmpty) {
              audioUrl = ytFreshUrl;
              _warmedStreamUrls[song.id] = ytFreshUrl;
              if (_currentIndex >= 0 && _currentIndex < _queue.length) {
                _queue[_currentIndex] = _queue[_currentIndex].copyWith(previewUrl: ytFreshUrl);
              }
            }
          } catch (_) {}
        } else {
          print('[Audio] 🔗 No valid URL for "${song.title}". Fetching fresh stream URL...');
          try {
            final freshUrl = await _directService.getFreshStreamUrl(song.id);
            if (freshUrl != null && freshUrl.isNotEmpty) {
              audioUrl = freshUrl;
              // Update queue so re-queued retries or syncs have it
              if (_currentIndex >= 0 && _currentIndex < _queue.length) {
                _queue[_currentIndex] = _queue[_currentIndex].copyWith(previewUrl: freshUrl);
              }
            }
          } catch (_) {}
        }
      }

      // Abort if the user switched songs while we were fetching the URL
      if (_playSessionId != currentSession) {
        print('[Audio] ℹ️ Session changed after URL fetch, aborting');
        return;
      }

      if (audioUrl != null && audioUrl.isNotEmpty) {
        try {
          // Local file path (from on_audio_query) — use file URI directly
          if (!audioUrl.startsWith('http')) {
            print('[Audio] 📁 Playing local file: $audioUrl');
            await _audioPlayer.setAudioSource(AudioSource.uri(Uri.file(audioUrl)));
            await _audioPlayer.load();
            if (_playSessionId != currentSession) return;
            await _audioPlayer.play();
            _consecutiveFailures = 0;
            print('[Audio] ✅ Local file playback started');
            return;
          }

          // CDN-compatible browser headers — saavncdn.com blocks requests without
          // a proper browser User-Agent and Referer from jiosaavn.com
          final cdnHeaders = (song.isYoutubeImport || song.id.startsWith('yt_'))
              ? <String, String>{
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                }
              : <String, String>{
                  'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                  'Referer': 'https://www.jiosaavn.com/',
                  'Origin': 'https://www.jiosaavn.com',
                };
          if (_playSessionId != currentSession) {
            print('[Audio] ℹ️ Play session changed before setUrl(), aborting');
            return;
          }
          final sourceUri = Uri.tryParse(audioUrl);
          if (sourceUri == null || !sourceUri.hasScheme || sourceUri.host.isEmpty) {
            throw const FormatException('Invalid remote audio URL');
          }
          print('[Audio] ▶️ Using LockCachingAudioSource with headers for: $audioUrl');
          await _audioPlayer.setAudioSource(
            LockCachingAudioSource(sourceUri, headers: cdnHeaders),
          );
          if (_playSessionId != currentSession) {
            print('[Audio] ℹ️ Play session changed, aborting playback');
            return;
          }

          // Wait for buffering to complete for network streams
          print('[Audio] ℹ️ Checking processingState...');
          int bufferRetries = 0;
          while (bufferRetries < 5 && _audioPlayer.processingState == ProcessingState.loading) {
            await Future.delayed(const Duration(milliseconds: 100));
            bufferRetries++;
          }

          if (_playSessionId != currentSession) {
            print('[Audio] ℹ️ Play session changed after buffer delay, aborting');
            return;
          }
          print('[Audio] ℹ️ Invoking play()...');
          await _audioPlayer.play();
          _consecutiveFailures = 0; // ✅ Reset on successful play
          unawaited(_warmAdjacentStreams());
          print('[Audio] ✅ Playback started successfully!');
          return;
        } catch (e) {
          print('[Audio] ❌ Primary source failed: $e');

          // —— Detect "Platform player already exists" — ExoPlayer is stuck ——
          final isStuckPlayer = e.toString().contains('already exists') ||
              e.toString().contains('Platform player');

          // —— Detect expired / invalid CDN URL (including YouTube 403/410) ——
          final isSourceError = e.toString().contains('Source error') ||
              e.toString().contains('403') ||
              e.toString().contains('410') ||
              e.toString().contains('HttpDataSourceException');

          // —— Detect transient network failure (device reconnecting after AOD/sleep) ——
          final isConnectionError = e.toString().contains('Connection aborted') ||
              e.toString().contains('Connection reset') ||
              e.toString().contains('Connection refused') ||
              e.toString().contains('Failed host lookup');

          if (isConnectionError) {
            // Brief pause to let ExoPlayer's HTTP stack recover after reconnect
            print('[Audio] 📶 Network interruption detected. Waiting 1.5s and retrying...');
            await Future.delayed(const Duration(milliseconds: 1500));
            if (_playSessionId != currentSession) return;
            try {
              const cdnHeaders = {
                'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                'Referer': 'https://www.jiosaavn.com/',
                'Origin': 'https://www.jiosaavn.com',
              };
              await _audioPlayer.setAudioSource(
                LockCachingAudioSource(Uri.parse(audioUrl), headers: cdnHeaders),
              );
              if (_playSessionId != currentSession) return;
              await _audioPlayer.play();
              _consecutiveFailures = 0;
              print('[Audio] ✅ Network retry succeeded!');
              return;
            } catch (netRetryErr) {
              print('[Audio] ❌ Network retry also failed: $netRetryErr');
            }
          } else if (isStuckPlayer) {
            print('[Audio] 🔄 Detected stuck ExoPlayer! Resetting AudioPlayer instance...');
            await _resetPlayer();
            if (_playSessionId != currentSession) return;
            // Retry the same song with the fresh player
            print('[Audio] 🔁 Retrying "${song.title}" with fresh player...');
            try {
              final cdnHeaders = (song.isYoutubeImport || song.id.startsWith('yt_'))
                  ? <String, String>{
                      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    }
                  : <String, String>{
                      'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                      'Referer': 'https://www.jiosaavn.com/',
                      'Origin': 'https://www.jiosaavn.com',
                    };
              if (audioUrl.startsWith('http')) {
                await _audioPlayer.setUrl(audioUrl, headers: cdnHeaders);
              } else {
                await _audioPlayer.setAudioSource(AudioSource.uri(Uri.file(audioUrl)));
              }
              if (_playSessionId != currentSession) return;
              await _audioPlayer.play();
              _consecutiveFailures = 0;
              print('[Audio] ✅ Retry after player reset succeeded!');
              return;
            } catch (retryErr) {
              print('[Audio] ❌ Retry after reset also failed: $retryErr');
            }
          } else if (isSourceError && (song.isYoutubeImport || song.id.startsWith('yt_') || song.youtubeUrl != null)) {
            // YouTube stream URL expired (HTTP 403 / 410) — re-extract fresh direct stream URL from microservice
            print('[Audio] 🔗 YouTube stream URL expired (403/410/Source error). Re-extracting for: ${song.title}...');
            try {
              final freshUrl = await _ytExtractor.getFreshStreamUrl(song);
              if (freshUrl != null && freshUrl.isNotEmpty) {
                print('[Audio] ✅ Got fresh YouTube stream URL. Updating queue + retrying...');
                if (_playSessionId != currentSession) return;

                if (_currentIndex < _queue.length) {
                  _queue[_currentIndex] = _queue[_currentIndex].copyWith(previewUrl: freshUrl);
                }

                await _audioPlayer.setAudioSource(
                  LockCachingAudioSource(Uri.parse(freshUrl)),
                );
                if (_playSessionId != currentSession) return;
                await _audioPlayer.play();
                _consecutiveFailures = 0;
                print('[Audio] ✅ Playback resumed with fresh YouTube stream URL!');
                return;
              }
            } catch (ytRefreshErr) {
              print('[Audio] ❌ YouTube stream refresh error: $ytRefreshErr');
            }
          } else if (isSourceError && song.id.isNotEmpty) {
            // CDN URL is expired — fetch a fresh one and retry
            print('[Audio] 🔗 CDN URL expired. Fetching fresh stream URL for song ID: ${song.id}...');
            try {
              final freshUrl = await _directService.getFreshStreamUrl(song.id);
              if (freshUrl != null && freshUrl.isNotEmpty) {
                print('[Audio] ✅ Got fresh URL. Updating queue + retrying...');
                if (_playSessionId != currentSession) return;

                // Persist the fresh URL into the queue so re-queued retries
                // don't hit the same expired CDN token again
                if (_currentIndex < _queue.length) {
                  _queue[_currentIndex] = _queue[_currentIndex].copyWith(previewUrl: freshUrl);
                }

                const cdnHeaders = {
                  'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                  'Referer': 'https://www.jiosaavn.com/',
                  'Origin': 'https://www.jiosaavn.com',
                };
                await _audioPlayer.setUrl(freshUrl, headers: cdnHeaders);
                if (_playSessionId != currentSession) return;
                await _audioPlayer.play();
                _consecutiveFailures = 0;
                print('[Audio] ✅ Playback started with fresh URL!');
                return;
              } else {
                print('[Audio] ⚠️ Could not get fresh URL for ${song.title} — skipping');
              }
            } catch (refreshErr) {
              print('[Audio] ❌ Fresh URL fetch/play also failed: $refreshErr');
            }
          } else {
            // Fallback: try AudioSource.uri in case setUrl failed for another reason
            try {
              print('[Audio] 🔄 Fallback: trying AudioSource.uri with headers...');
              await _audioPlayer.stop();
              await Future.delayed(const Duration(milliseconds: 50));
              const cdnHeaders = {
                'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                'Referer': 'https://www.jiosaavn.com/',
                'Origin': 'https://www.jiosaavn.com',
              };
              await _audioPlayer.setAudioSource(
                AudioSource.uri(Uri.parse(audioUrl), headers: cdnHeaders),
              );
              if (_playSessionId != currentSession) return;
              print('[Audio] ℹ️ Invoking play() for fallback AudioSource.uri...');
              await _audioPlayer.play();
              _consecutiveFailures = 0;
              print('[Audio] ✅ Fallback AudioSource.uri playback started');
              return;
            } catch (e2) {
              print('[Audio] ❌ Fallback AudioSource.uri also failed: $e2');
            }
          }
        }
      } else {
        print('[Audio] ⚠️ No audio URL found for this song');
        // Explicitly handle unstreamable track by skipping it
        _consecutiveFailures++;
        if (_consecutiveFailures >= 2) {
          await _resetPlayer();
        }
        if (_queue.length > 1) {
          _currentIndex = (_currentIndex + 1) % _queue.length;
          _playSong(_getSafeQueueSong(_currentIndex) ?? _queue[_currentIndex]);
        } else {
          _audioPlayer.stop();
        }
        return;
      }

      // ── Failure recovery: skip to next instead of stopping the entire queue ──
      _consecutiveFailures++;
      print('[Audio] ⚠️ Song failed to play. Consecutive failures: $_consecutiveFailures/$_maxConsecutiveFailures');

      // Reset the player if it keeps failing — clears any stuck ExoPlayer state
      // so the next song has a clean player to load into
      if (_consecutiveFailures >= 2) {
        print('[Audio] 🔄 Resetting player due to repeated failures...');
        await _resetPlayer();
      }

      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        print('[Audio] 🛑 Too many consecutive failures. Stopping playback.');
        _consecutiveFailures = 0;
        await stop();
      } else if (_currentIndex < _queue.length - 1) {
        print('[Audio] ⏭️ Auto-skipping to next song after failure...');
        _currentIndex++;
        final nextSong = _getSafeQueueSong(_currentIndex);
        if (nextSong != null) {
          _currentSongController.add(nextSong);
          await _playSong(nextSong);
        } else {
          await stop();
        }
      } else if (_context == PlaybackContext.search || _context == PlaybackContext.radio) {
        print('[Audio] 🤖 End of queue after failure. Fetching algorithm recommendations...');
        _playNextAlgorithmSong();
      } else {
        print('[Audio] ⏹ End of queue after failure. Stopping.');
        await stop();
      }
    } catch (e, stackTrace) {
      print('[Audio] ❌ Critical error in _playSong: $e');
      print('[Audio] Stack trace: $stackTrace');
      _consecutiveFailures++;
      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        _consecutiveFailures = 0;
        await stop();
      } else if (_currentIndex < _queue.length - 1) {
        _currentIndex++;
        final nextSong = _getSafeQueueSong(_currentIndex);
        if (nextSong != null) {
          _currentSongController.add(nextSong);
          _isPlayingSong = false;
          await _playSong(nextSong);
          return;
        }
        await stop();
      } else {
        await stop();
      }
    } finally {
      _isPlayingSong = false;
    }
  }

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    if (duration == Duration.zero) return;
    
    print('[Sleep Timer] Set for ${duration.inMinutes} minutes');
    _sleepTimer = Timer(duration, () {
      print('[Sleep Timer] 😴 Time up! Stopping playback');
      stop();
    });
  }

  bool get isSleepTimerActive => _sleepTimer?.isActive ?? false;

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
  }

  @override
  Future<void> play() async {
    try { 
      await _audioPlayer.play();
      print('[Audio] ▶️ Play command executed');
    } catch (e) { 
      print('[Audio] ❌ Play error: $e'); 
    }
  }

  @override
  Future<void> pause() async {
    try { 
      await _audioPlayer.pause();
      print('[Audio] ⏸️ Pause command executed');
    } catch (e) { 
      print('[Audio] ❌ Pause error: $e'); 
    }
  }

  // ── Navigation ──────────────────────────────────────────────────────────
  /// Insert a song to play next (right after current song)
  /// Used by 'Play Next' button in song context menus
  Future<void> playNext(Song song) async {
    try {
      print('[Audio] ⏭️ Play next: "${song.title}" after current song');
      if (_currentIndex >= 0 && _currentIndex < _queue.length) {
        // Insert song right after current song
        final insertIndex = _currentIndex + 1;
        _queue.insert(insertIndex, song);
        _originalQueue.insert(insertIndex, song);
        print('[Audio] ✅ Song queued to play next at index $insertIndex');
      }
    } catch (e) {
      print('[Audio] ❌ Play next error: $e');
    }
  }

  @override
  Future<void> skipToNext() async {
    try {
      print('[Audio] ⏭️ Skip to next requested');
      if (_queue.isEmpty) {
        print('[Audio] ⚠️ Cannot skip: queue is empty');
        return;
      }

      _skipDebounceTimer?.cancel();
      _skipDebounceTimer = Timer(const Duration(milliseconds: 250), () {});

      if (_currentIndex < _queue.length - 1) {
        _currentIndex++;
        final nextSong = _getSafeQueueSong(_currentIndex);
        if (nextSong != null) {
          _currentSongController.add(nextSong);
          await _playSong(nextSong);
        } else {
          print('[Audio] ⚠️ Skip failed: next song is null');
        }
      } else if (_repeatMode == AudioServiceRepeatMode.all) {
        _currentIndex = 0;
        final firstSong = _getSafeQueueSong(_currentIndex);
        if (firstSong != null) {
          _currentSongController.add(firstSong);
          await _playSong(firstSong);
        }
      } else if (_context == PlaybackContext.album || _context == PlaybackContext.playlist || _context == PlaybackContext.local) {
        print('[Audio] ⏹ Skip reached end of ${_context.name} queue.');
        _audioPlayer.stop();
      } else {
        _playNextAlgorithmSong();
      }
    } catch (e, stackTrace) {
      print('[Audio] ❌ Skip next error: $e');
      print('[Audio] Stack trace: $stackTrace');
      if (_currentIndex >= 0 && _currentIndex < _queue.length) {
        final currentSong = _getSafeQueueSong(_currentIndex);
        if (currentSong != null) {
          _currentSongController.add(currentSong);
        }
      }
    }
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      print('[Audio] ⏮️ Skip to previous requested');
      if (_queue.isEmpty) {
        print('[Audio] ⚠️ Cannot skip: queue is empty');
        return;
      }

      _skipDebounceTimer?.cancel();
      _skipDebounceTimer = Timer(const Duration(milliseconds: 250), () {});

      if (_audioPlayer.position.inSeconds > 3) {
        await _audioPlayer.seek(Duration.zero);
      } else if (_currentIndex > 0) {
        _currentIndex--;
        final prevSong = _getSafeQueueSong(_currentIndex);
        if (prevSong != null) {
          _currentSongController.add(prevSong);
          await _playSong(prevSong);
        }
      } else if (_repeatMode == AudioServiceRepeatMode.all) {
        _currentIndex = _queue.length - 1;
        final lastSong = _getSafeQueueSong(_currentIndex);
        if (lastSong != null) {
          _currentSongController.add(lastSong);
          await _playSong(lastSong);
        }
      } else {
        _playNextAlgorithmSong();
      }
    } catch (e, stackTrace) {
      print('[Audio] ❌ Skip previous error: $e');
      print('[Audio] Stack trace: $stackTrace');
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    // TASK 3 FIX: Fisher-Yates shuffle with original-order preservation
    if (shuffleMode == AudioServiceShuffleMode.all &&
        _shuffleMode != AudioServiceShuffleMode.all) {
      // ── Turning shuffle ON ───────────────────────────────────────────
      final currentlyPlaying = _queue.isNotEmpty ? _queue[_currentIndex] : null;

      // Fisher-Yates in-place shuffle of a working copy
      final shuffled = List<Song>.from(_queue);
      final rng = Random();
      for (int i = shuffled.length - 1; i > 0; i--) {
        final j = rng.nextInt(i + 1);
        final temp = shuffled[i];
        shuffled[i] = shuffled[j];
        shuffled[j] = temp;
      }

      // Place the currently playing song first so playback doesn't jump
      if (currentlyPlaying != null) {
        shuffled.remove(currentlyPlaying);
        shuffled.insert(0, currentlyPlaying);
      }

      _queue
        ..clear()
        ..addAll(shuffled);
      _currentIndex = 0; // currently playing song is now at index 0

    } else if (shuffleMode == AudioServiceShuffleMode.none &&
        _shuffleMode == AudioServiceShuffleMode.all) {
      // ── Turning shuffle OFF ──────────────────────────────────────────
      final currentlyPlaying = _queue.isNotEmpty ? _queue[_currentIndex] : null;

      // Restore original order
      _queue
        ..clear()
        ..addAll(_originalQueue);

      // Find the current song's position in the restored order and seek to it
      if (currentlyPlaying != null) {
        final restoredIndex =
            _queue.indexWhere((s) => s.id == currentlyPlaying.id);
        _currentIndex = restoredIndex >= 0 ? restoredIndex : 0;
      } else {
        _currentIndex = 0;
      }
      // NOTE: No _playSong() call here — the song keeps playing seamlessly.
    }

    _shuffleMode = shuffleMode;
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    print('[Audio] 🔀 Shuffle: ${shuffleMode == AudioServiceShuffleMode.all ? "ON" : "OFF"} '
        '| queue length: ${_queue.length} | current index: $_currentIndex');
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    // Repeat logic completely managed by _onTrackEnded gatekeeper
    // We enforce LoopMode.off natively to maintain explicit state control
    await _audioPlayer.setLoopMode(LoopMode.off);

    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    print('[Audio] 🔁 Repeat: $repeatMode | LoopMode: '
        '${repeatMode == AudioServiceRepeatMode.one ? "one" : "off"}');
  }

  @override
  Future<void> seek(Duration position) async {
    try { 
      await _audioPlayer.seek(position);
      print('[Audio] ⏩ Seek to ${position.inSeconds}s');
    } catch (e) { 
      print('[Audio] ❌ Seek error: $e'); 
    }
  }

  @override
  Future<void> stop() async {
    try { 
      await _audioPlayer.stop();
      print('[Audio] ⏹️ Stop command executed');
    } catch (e) { 
      print('[Audio] ❌ Stop error: $e'); 
    }
  }

  // Pre-fetched recommendations to ensure zero-latency transitions
  List<Song>? _preFetchedQueue;
  String? _preFetchedForSongId;

  Future<void> _prepareNextAlgorithmSong() async {
    if (_context == PlaybackContext.local) return;
    final seedSong = _queue.isNotEmpty ? _queue[_currentIndex] : null;
    if (seedSong == null) return;
    
    if (_preFetchedForSongId == seedSong.id) return; // Already prepared

    final int currentSession = _playSessionId;

    print('[Hybrid Engine] ⚡ Pre-fetching next-gen 4-way hybrid recommendations for "${seedSong.title}"...');
    
    try {
      final List<Song> candidates = [];
      final Set<String> seenIds = {seedSong.id}; // Don't recommend the current song
      
      // Let's run A and B concurrently, plus fetch global transitions from Firestore!
      final futures = await Future.wait([
        _mlEngine.deliverRecommendations(seedSong: seedSong, limit: 10),
        _hybridSearch.getTrendingTracks(limit: 10),
      ]);
      
      final globalTransitions = await _globalEngine.getGlobalTransitions(seedSong.id);
      
      for (final list in futures) {
        for (final song in list) {
          if (!seenIds.contains(song.id) && !_isDuplicateSong(song)) {
            candidates.add(song);
            seenIds.add(song.id);
          }
        }
      }

      // If we still don't have enough candidates, fallback to artist search
      if (candidates.length < 5) {
        final artistQuery = seedSong.artist.split(',').first.trim();
        final fallback = await _hybridSearch.searchSongs(artistQuery, limit: 10);
        for (final song in fallback) {
          if (!seenIds.contains(song.id) && !_isDuplicateSong(song)) {
            candidates.add(song);
            seenIds.add(song.id);
          }
        }
      }

      // Now apply the Next-Gen 4-Way Hybrid Scoring Pipeline
      // Pass 1: Candidates already gathered.
      
      // Fetch Metric B: Global Play Counts (Velocity)
      final globalPlayCounts = await _globalEngine.getGlobalPlayCounts(candidates.map((c) => c.id).toList());
      // Fetch Metric C: Market Trends (simplified by checking trending API response)
      final trendingTracks = await _hybridSearch.getTrendingTracks(limit: 50);
      final trendingIds = trendingTracks.map((t) => t.id).toSet();

      // Extract all local taste matrix features
      final seedTransitions = Map<String, int>.from(
        _tasteEngine.getTransitionsForSong(seedSong.id).map(
          (k, v) => MapEntry(k.toString(), v as int? ?? 0)
        )
      );
      final topArtists = _tasteEngine.getTopArtists();
      
      final favoriteSongIds = <String>{};
      final customPlaylistSongIds = <String>{};
      if (Hive.isBoxOpen('userPlaylists')) {
        final playlistsBox = Hive.box<String>('userPlaylists');
        for (final key in playlistsBox.keys) {
          final val = playlistsBox.get(key);
          if (val is String) {
            try {
              final playlistMap = jsonDecode(val) as Map<String, dynamic>;
              final playlistId = playlistMap['id']?.toString() ?? '';
              final songsList = playlistMap['songs'] as List? ?? [];
              for (final s in songsList) {
                if (s is Map && s['id'] != null) {
                  final id = s['id'].toString();
                  if (playlistId == 'favorites_playlist_id') {
                    favoriteSongIds.add(id);
                  } else {
                    customPlaylistSongIds.add(id);
                  }
                }
              }
            } catch (_) {}
          }
        }
      }

      final recentSongPlayCounts = <String, int>{};
      if (Hive.isBoxOpen('recentlyPlayed')) {
        final recentlyBox = Hive.box<String>('recentlyPlayed');
        final list = recentlyBox.values.toList();
        for (final val in list) {
          if (val.isNotEmpty) {
            try {
              final songMap = jsonDecode(val) as Map<String, dynamic>;
              final id = songMap['id']?.toString();
              if (id != null) {
                recentSongPlayCounts[id] = (recentSongPlayCounts[id] ?? 0) + 1;
              }
            } catch (_) {}
          }
        }
      }

      final songHistoryCounts = Map<String, int>.from(
        _tasteEngine.getSongHistory().map(
          (k, v) => MapEntry(k.toString(), v as int? ?? 0)
        )
      );

      final payload = RecommendationComputePayload(
        seedSongMap: seedSong.toJson(),
        candidateSongMaps: candidates.map((c) => c.toJson()).toList(),
        globalTransitions: globalTransitions,
        globalPlayCounts: globalPlayCounts,
        trendingIds: trendingIds,
        playHistoryMaps: _playHistory.map((h) => h.toJson()).toList(),
        seedTransitions: seedTransitions,
        topArtists: topArtists,
        favoriteSongIds: favoriteSongIds,
        customPlaylistSongIds: customPlaylistSongIds,
        recentSongPlayCounts: recentSongPlayCounts,
        songHistoryCounts: songHistoryCounts,
      );

      print('[Hybrid Engine] 🤖 Offloading 4-way hybrid scoring to background Isolate...');
      final finalQueue = await compute(_calculateAffinityScores, payload);
      
      // Strict Mutex Lock Check: if the user initiated manual navigation, abort.
      if (currentSession != _playSessionId) {
        print('[Hybrid Engine] 🛑 Aborting pre-fetch: Play session was interrupted manually.');
        return;
      }

      if (finalQueue.isNotEmpty) {
        _preFetchedQueue = finalQueue;
        _preFetchedForSongId = seedSong.id;
        print('[Hybrid Engine] ✅ Pre-fetched and scored ${finalQueue.length} tracks.');
      }
    } catch (e) {
      print('[Hybrid Engine] ⚠️ Pre-fetch failed: $e');
    }
  }

  Future<void> _playNextAlgorithmSong() async {
    if (_context == PlaybackContext.local) return;

    if (_preFetchedQueue != null && _preFetchedQueue!.isNotEmpty) {
      print('[Hybrid Engine] 🚀 Playing zero-latency pre-fetched queue!');
      await _loadAndPlayAlgorithmQueue(_preFetchedQueue!, 'Native 4-Way Hybrid');
      _preFetchedQueue = null; // Clear after use
      return;
    }
    
    // If not pre-fetched, prepare now and play
    await _prepareNextAlgorithmSong();
    if (_preFetchedQueue != null && _preFetchedQueue!.isNotEmpty) {
      await _loadAndPlayAlgorithmQueue(_preFetchedQueue!, 'Native 4-Way Hybrid');
      _preFetchedQueue = null;
    } else {
      print('[Hybrid Engine] ❌ All recommendations failed. Stopping playback.');
      await stop();
    }
  }

  Future<void> _loadAndPlayAlgorithmQueue(List<Song> songs, String sourceName) async {
    final validSongs = songs.where((s) => s.previewUrl != null && s.previewUrl!.isNotEmpty).toList();
    if (validSongs.isEmpty) return;

    print('[Hybrid Engine] 🚀 Loading $sourceName queue with ${validSongs.length} items. Playing: "${validSongs.first.title}"');
    _queue.clear();
    _originalQueue.clear();
    _queue.addAll(validSongs);
    _originalQueue.addAll(validSongs);
    _currentIndex = 0;
    _context = PlaybackContext.radio;
    await _playSong(_queue[_currentIndex]);
  }

  // REMOVED FIREBASE CALLS

  SongModel _parseSong(Map<String, dynamic> r) {
    // Artists — join primary artists
    final primaryArtists = r['artists']?['primary'] as List? ?? [];
    final artistName = primaryArtists
        .map((a) => a['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');

    // Album art — use highest quality (500x500)
    final images = r['image'] as List? ?? [];
    final albumArt = images.isNotEmpty ? (images.last['url'] as String?) : null;

    // Download URL — use highest quality (320kbps)
    final dlUrls = r['downloadUrl'] as List? ?? [];
    final downloadUrl = dlUrls.isNotEmpty ? (dlUrls.last['url'] as String?) : null;

    // Duration in seconds
    final durationSec = r['duration'];
    final duration = Duration(
      seconds: durationSec is int
          ? durationSec
          : (int.tryParse(durationSec?.toString() ?? '0') ?? 0),
    );

    return SongModel(
      id: r['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: r['name'] ?? 'Unknown',
      artist: artistName.isNotEmpty ? artistName : 'Unknown Artist',
      albumArt: albumArt,
      album: r['album']?['name'],
      duration: duration,
      previewUrl: downloadUrl,
    );
  }

  Song? get currentSong => _queue.isNotEmpty ? _queue[_currentIndex] : null;
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<Duration> get uiPositionStream => _uiPositionController.stream;
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;
  Stream<bool> get playingStream => _audioPlayer.playingStream;

  /// Handle screen state changes to maintain audio playback during AOD transitions
  Future<void> handleScreenStateChange({required bool isScreenOn, required bool isAODActive}) async {
    try {
      print('[Audio] 📱 Screen state change: screenOn=$isScreenOn, AOD=$isAODActive');
      
      // Ensure audio playback is maintained during screen state changes.
      // The current just_audio version does not expose setAudioAttributes.
      
      // If transitioning to AOD and music was playing, ensure it continues
      if (isAODActive && playbackState.value.playing) {
        print('[Audio] 🔄 Maintaining playback during AOD transition');
        // Small delay to let native AOD setup complete
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Ensure playback is still active
        if (!_audioPlayer.playing && playbackState.value.playing) {
          await _audioPlayer.play();
          print('[Audio] ✅ Restored playback after AOD transition');
        }
      }
    } catch (e) {
      print('[Audio] ❌ Error handling screen state change: $e');
    }
  }

  /// Ensure audio focus is maintained during screen transitions
  Future<void> maintainAudioFocus() async {
    try {
      // just_audio currently manages audio focus internally via AudioService.
      print('[Audio] 🎵 Audio focus maintain request received');
    } catch (e) {
      print('[Audio] ❌ Failed to maintain audio focus: $e');
    }
  }



  void dispose() {
    _uiPositionSourceSub?.cancel();
    _uiPositionTimer?.cancel();
    _uiPositionController.close();
    _currentSongController.close();
    _dio.close();
    _hybridSearch.dispose();
    _mlEngine.dispose();
    _audioPlayer.dispose();
  }
}

class SongModel extends Song {
  SongModel({
    required super.id,
    required super.title,
    required super.artist,
    super.album,
    super.albumArt,
    required super.duration,
    super.previewUrl,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate Recommendation Scoring DTO & Processor
// ─────────────────────────────────────────────────────────────────────────────

class RecommendationComputePayload {
  final Map<String, dynamic> seedSongMap;
  final List<Map<String, dynamic>> candidateSongMaps;
  final Map<String, int> globalTransitions;
  final Map<String, int> globalPlayCounts;
  final Set<String> trendingIds;
  final List<Map<String, dynamic>> playHistoryMaps;
  
  // Local Taste Matrix parameters
  final Map<String, int> seedTransitions;
  final List<String> topArtists;
  final Set<String> favoriteSongIds;
  final Set<String> customPlaylistSongIds;
  final Map<String, int> recentSongPlayCounts;
  final Map<String, int> songHistoryCounts;

  RecommendationComputePayload({
    required this.seedSongMap,
    required this.candidateSongMaps,
    required this.globalTransitions,
    required this.globalPlayCounts,
    required this.trendingIds,
    required this.playHistoryMaps,
    required this.seedTransitions,
    required this.topArtists,
    required this.favoriteSongIds,
    required this.customPlaylistSongIds,
    required this.recentSongPlayCounts,
    required this.songHistoryCounts,
  });
}

/// Static top-level processor executing entirely on a background Isolate thread.
List<Song> _calculateAffinityScores(RecommendationComputePayload payload) {
  final seedSong = Song.fromJson(payload.seedSongMap);
  final candidates = payload.candidateSongMaps.map((m) => Song.fromJson(m)).toList();
  final playHistory = payload.playHistoryMaps.map((m) => Song.fromJson(m)).toList();

  final seedLang = _inferLanguageStatic(seedSong);

  // Track consecutive played count of seedLang in playHistory to prevent silos
  int consecutiveLanguageCount = 0;
  for (int i = playHistory.length - 1; i >= 0; i--) {
    if (_inferLanguageStatic(playHistory[i]) == seedLang) {
      consecutiveLanguageCount++;
    } else {
      break;
    }
  }

  final scoredCandidates = candidates.map((song) {
    // 1. Calculate local affinity score
    double score = 0.0;

    // Co-occurrence check
    final int transitionCount = payload.seedTransitions[song.id] ?? 0;
    if (transitionCount > 0) {
      score += (transitionCount * 5.0);
    }

    // Top artist affinity
    final candidateArtists = song.artist.split(',').map((e) => e.trim());
    for (final artist in candidateArtists) {
      if (payload.topArtists.contains(artist)) {
        score += 1.5;
      }
    }

    // Favorites & Custom Playlist checks
    if (payload.favoriteSongIds.contains(song.id)) {
      score += 3.0;
    } else if (payload.customPlaylistSongIds.contains(song.id)) {
      score += 2.0;
    }

    // Recently Played check
    final recentCount = payload.recentSongPlayCounts[song.id] ?? 0;
    if (recentCount > 0) {
      score += (recentCount * 1.0);
    }

    // Overall song frequency play count check
    final int songPlayCount = payload.songHistoryCounts[song.id] ?? 0;
    if (songPlayCount > 0) {
      score += (songPlayCount * 0.5);
    }

    // 2. Global transitions
    if (payload.globalTransitions.containsKey(song.id)) {
      score += (payload.globalTransitions[song.id]! * 2.0);
    }

    // 3. Global play counts
    if (payload.globalPlayCounts.containsKey(song.id)) {
      final count = payload.globalPlayCounts[song.id]!;
      if (count > 0) {
        score *= (1.0 + (count * 0.01));
      }
    }

    // 4. Market trends
    if (payload.trendingIds.contains(song.id)) {
      score *= 1.4;
    }

    // 5. Regional Linguistic modifier
    final candidateLang = _inferLanguageStatic(song);
    double linguisticModifier = 1.0;

    // Linguistic Weighting
    if (candidateLang == seedLang) {
      linguisticModifier *= 1.5;
    }

    // Silo Prevention
    if (consecutiveLanguageCount >= 4 && candidateLang == seedLang) {
      linguisticModifier *= 0.3;
    } else if (consecutiveLanguageCount >= 4 && candidateLang != seedLang) {
      linguisticModifier *= 2.0;
    }

    // Cross-Language Leakage Bridges
    if (seedLang == 'hindi' && candidateLang == 'punjabi') {
      linguisticModifier *= 1.3;
    } else if (seedLang == 'hindi' && candidateLang == 'bhojpuri') {
      linguisticModifier *= 1.2;
    } else if (seedLang == 'bengali' && candidateLang == 'hindi') {
      linguisticModifier *= 1.4;
    } else if (seedLang == 'bhojpuri' && candidateLang == 'hindi') {
      linguisticModifier *= 1.3;
    }

    score *= linguisticModifier;

    // Recency Penalty (Strict loop prevention)
    if (playHistory.any((h) => h.id == song.id)) {
      score = 0.0;
    }

    // Add random slight variance to break ties
    if (score > 0) {
      score += (Random().nextDouble() * 0.5);
    }

    return MapEntry(song, score);
  }).toList();

  // Sort by score descending
  scoredCandidates.sort((a, b) => b.value.compareTo(a.value));

  // Take top 10
  return scoredCandidates.take(10).map((e) => e.key).toList();
}

/// Helper method to statically infer song language in the background Isolate.
String _inferLanguageStatic(Song song) {
  // 1. Direct check
  if (song.language != null && song.language!.isNotEmpty) {
    final lang = song.language!.toLowerCase();
    if (lang.contains('hindi') || lang == 'hi') return 'hindi';
    if (lang.contains('punjabi') || lang == 'pa') return 'punjabi';
    if (lang.contains('bhojpuri')) return 'bhojpuri';
    if (lang.contains('bengali') || lang == 'bn') return 'bengali';
    return lang;
  }

  final titleLower = song.title.toLowerCase();
  final artistLower = song.artist.toLowerCase();

  // 2. Artist profile check
  const Map<String, String> artistLanguageMap = {
    'arijit singh': 'hindi',
    'shreya ghoshal': 'hindi',
    'alka yagnik': 'hindi',
    'udit narayan': 'hindi',
    'kumar sanu': 'hindi',
    'diljit dosanjh': 'punjabi',
    'ap dhillon': 'punjabi',
    'guru randhawa': 'punjabi',
    'b praak': 'punjabi',
    'pawan singh': 'bhojpuri',
    'khesari lal yadav': 'bhojpuri',
    'shilpi raj': 'bhojpuri',
    'anupam roy': 'bengali',
    'rupanakr': 'bengali',
    'shaan': 'hindi',
    'sidhu moose wala': 'punjabi',
  };

  for (final entry in artistLanguageMap.entries) {
    if (artistLower.contains(entry.key)) {
      return entry.value;
    }
  }

  // 3. Token-based phonetic dictionary analysis
  const Map<String, Set<String>> phoneticDictionaries = {
    'hindi': {
      'pyar', 'pyaar', 'dil', 'mera', 'ishq', 'teri', 'tere', 'meri', 'tujhe', 'tum', 
      'se', 'hai', 'ki', 'ka', 'ke', 'aur', 'na', 'jiya', 'dhadkan', 'sanam', 'tu', 'mujhse', 'hum', 
      'tumhare', 'zindagi', 'mohabbat', 'dost', 'yaar', 'yaara', 'jaane', 'jaana', 'raahi', 'ho', 'gaya',
      'ek', 'do', 'teen', 'main', 'hoon', 'kya', 'batayein', 'kaise', 'mile', 'chalte', 'duniya', 'dhadak'
    },
    'punjabi': {
      'kudi', 'munda', 'gabru', 'pind', 'punjabi', 'jatt', 've', 'bhangra', 'dhol', 'nach', 'suit', 
      'nakhra', 'gaddi', 'gaddiyaan', 'mittran', 'ni', 'hath', 'sardar', 'singh', 'kaur', 'panjabo',
      'naal', 'changa', 'vadiya', 'kol', 'chadd', 'viah', 'je', 'patiala'
    },
    'bhojpuri': {
      'kamariya', 'lagawe', 'lipistick', 'lipistik', 'bhojpuri', 'gori', 'tohar', 'ba', 'laika', 
      'choli', 'bhatar', 'sautin', 'patna', 'pawan', 'khesari', 'lahanga', 'marad', 'maro', 'saiyaan', 
      'bhojpuria', 'tore', 'maai', 'piya', 'kajar', 'luliya', 'hamar'
    },
    'bengali': {
      'bengali', 'bangla', 'tumi', 'aami', 'bhalobashi', 'amar', 'tomar', 'kothay', 'mon', 'bhalo', 
      'shundor', 'gaan', 'brishti', 'shonar', 'chaai', 'hobe', 'kotha', 'dekha', 'bhalobasa', 'golpo',
      'bhalobese', 'moner', 'kache', 'chara', 'keu'
    },
  };

  final tokens = titleLower.split(RegExp(r'[^a-zA-Z0-9]+')).where((t) => t.isNotEmpty);
  final scores = <String, int>{'hindi': 0, 'punjabi': 0, 'bhojpuri': 0, 'bengali': 0};

  for (final token in tokens) {
    for (final lang in phoneticDictionaries.keys) {
      if (phoneticDictionaries[lang]!.contains(token)) {
        scores[lang] = scores[lang]! + 1;
      }
    }
  }

  String? bestLang;
  int maxScore = 0;
  scores.forEach((lang, score) {
    if (score > maxScore) {
      maxScore = score;
      bestLang = lang;
    }
  });

  if (maxScore > 0 && bestLang != null) {
    return bestLang!;
  }

  // 4. Substring fallback checks
  if (titleLower.contains('bhojpuri')) return 'bhojpuri';
  if (titleLower.contains('punjabi')) return 'punjabi';
  if (titleLower.contains('bengali') || titleLower.contains('bangla')) return 'bengali';

  return 'hindi';
}

