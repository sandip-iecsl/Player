import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:dio/dio.dart';
import '../../domain/entities/song.dart';
import 'ml_recommendation_engine.dart';

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
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));
  
  // ML Recommendation Engine
  final MLRecommendationEngine _mlEngine = MLRecommendationEngine();

  // ── Queue state ───────────────────────────────────────────────────────────
  /// The currently active playback queue (may be shuffled).
  final List<Song> _queue = [];

  /// Preserves the original, un-shuffled order so shuffle can be reversed.
  final List<Song> _originalQueue = [];

  int _currentIndex = 0;

  /// Loaded context — determines end-of-queue behaviour.
  PlaybackContext _context = PlaybackContext.radio;

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

  AudioServiceHandler() {
    _initWakeMode();
    _setupPlayerListeners();
    _setupScreenStateListener();
  }

  Future<void> _initWakeMode() async {
    try {
      await _audioPlayer.setWakeMode(WakeMode.audio);
      print('[Audio] 💤 WakeLock enabled (WakeMode.audio)');
    } catch (e) {
      print('[Audio] ❌ Failed to set wake mode: $e');
    }
  }

  Future<void> _setupScreenStateListener() async {
    // Listen for screen state changes to maintain audio playback during AOD transitions
    try {
      // No explicit AudioAttributes API is available in the current just_audio version.
      // AudioService handles focus and playback lifecycle automatically.
      print('ℹ️ Screen state listener initialized');
    } catch (e) {
      print('❌ Failed to initialize screen state listener: $e');
    }
  }

  void _setupPlayerListeners() {
    // ── Enhanced Playback state mirror with stylish notification controls ────────────────────────────────────────────────
    _audioPlayer.playbackEventStream.listen((event) {
      final isPlaying = _audioPlayer.playing;
      final processingState = _audioPlayer.processingState;
      
      playbackState.add(playbackState.value.copyWith(
        controls: [
          // Enhanced controls with custom icons and better styling
          const MediaControl(
            androidIcon: 'drawable/ic_skip_previous',
            label: 'Previous',
            action: MediaAction.skipToPrevious,
          ),
          if (isPlaying)
            const MediaControl(
              androidIcon: 'drawable/ic_pause_circle',
              label: 'Pause',
              action: MediaAction.pause,
            )
          else
            const MediaControl(
              androidIcon: 'drawable/ic_play_circle',
              label: 'Play',
              action: MediaAction.play,
            ),
          const MediaControl(
            androidIcon: 'drawable/ic_skip_next',
            label: 'Next',
            action: MediaAction.skipToNext,
          ),
          // Add favorite/like control for enhanced interaction
          const MediaControl(
            androidIcon: 'drawable/ic_favorite_border',
            label: 'Like',
            action: MediaAction.setRating,
          ),
          // Add repeat control
          MediaControl(
            androidIcon: _repeatMode == AudioServiceRepeatMode.all 
                ? 'drawable/ic_repeat_on'
                : _repeatMode == AudioServiceRepeatMode.one
                    ? 'drawable/ic_repeat_one'
                    : 'drawable/ic_repeat_off',
            label: 'Repeat',
            action: MediaAction.setRepeatMode,
          ),
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
          MediaAction.setRating,
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
        // Enhanced for better lock screen and notification display
        androidCompactActionIndices: const [0, 1, 2], // Previous, Play/Pause, Next
      ));
    });

    // Listen to playing state changes for immediate notification updates
    _audioPlayer.playingStream.listen((playing) {
      playbackState.add(playbackState.value.copyWith(
        playing: playing,
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
      ));
    });

    // ── Track-ended gatekeeper ───────────────────────────────────────────────
    // Evaluated in strict priority order:
    //  Gate 1 ▶ Repeat One  — LoopMode.one handles it inside just_audio; never fires here.
    //  Gate 2 ▶ Next track  — advance index sequentially (shuffled order if shuffle ON).
    //  Gate 3 ▶ Repeat All  — wrap back to index 0.
    //  Gate 4 ▶ Autoplay    — only for search / radio contexts.
    //  Gate 5 ▶ Stop        — clean stop for album / playlist / local.
    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        // Track song completion for ML engine
        if (_currentSong != null) {
          final completionRate = _audioPlayer.position.inSeconds / 
                                (_currentSong!.duration.inSeconds > 0 ? _currentSong!.duration.inSeconds : 1);
          _mlEngine.trackSongPlay(_currentSong!, completionRate: completionRate.clamp(0.0, 1.0));
          print('[ML] 📊 Tracked: ${_currentSong!.title} - Completion: ${(completionRate * 100).toStringAsFixed(1)}%');
        }
        _onTrackEnded();
      }
    });

    _audioPlayer.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) => print('[Audio] ❌ Player error: $e'),
    );
  }

  // ── onTrackEnded — the single structural gatekeeper ─────────────────────────
  void _onTrackEnded() {
    print('[Audio] 🏁 Track ended - Current index: $_currentIndex, Queue length: ${_queue.length}');
    
    // Step 1: Check Repeat One Gate
    if (_repeatMode == AudioServiceRepeatMode.one) {
      print('[Audio] 🔁 Repeat ONE - Replaying current track');
      seek(Duration.zero);
      play(); // Replay current track
      // Keep repeat mode ON - don't turn it off automatically
      return; // Exit function block
    }

    // Step 2: Check Active Queue Boundaries
    if (_currentIndex < _queue.length - 1) {
      print('[Audio] ➡️ Moving to next song in queue');
      _currentIndex++;
      _currentSongController.add(_queue[_currentIndex]);
      _playSong(_queue[_currentIndex]);
      return; // Exit function block
    }

    // Step 3: Check Repeat All Gate
    if (_repeatMode == AudioServiceRepeatMode.all) {
      print('[Audio] 🔁 Repeat ALL - Wrapping to start');
      _currentIndex = 0;
      _currentSongController.add(_queue[_currentIndex]);
      _playSong(_queue[_currentIndex]);
      return; // Exit function block
    }

    // Step 4: Execute Infinite Autoplay Fallback
    if (_context == PlaybackContext.album || _context == PlaybackContext.playlist) {
      print('[Audio] 🎵 Album/Playlist ended - Starting radio mode');
      _context = PlaybackContext.radio; // equivalent to NONE context type in spec
      _playNextAlgorithmSong(); // API fetch, clear queue, push tracks, play index 0
      return; // Exit function block
    }

    // Handle existing radio/search contexts ending
    if (_context == PlaybackContext.search || _context == PlaybackContext.radio) {
      print('[Audio] 🤖 Radio/Search ended - Generating next recommendations');
      _playNextAlgorithmSong();
      return;
    }

    // End of queue for local files — stopped.
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
    
    // Fallback: title + artist fuzzy match to catch exact same songs with different IDs
    final newTitle = newSong.title.replaceAll(RegExp(r'[\(\[\-\|].*'), '').trim().toLowerCase();
    final newArtist = newSong.artist.split(',').first.trim().toLowerCase();
    
    return _queue.any((q) {
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
  }) async {
    if (songs.isEmpty) return;
    _context = _inferContext(songs, context);
    _queue
      ..clear()
      ..addAll(songs);
    _originalQueue
      ..clear()
      ..addAll(songs);
    
    // Apply shuffle if it's already enabled
    if (_shuffleMode == AudioServiceShuffleMode.all) {
      print('[Audio] 🔀 Shuffle is ON - Shuffling new queue');
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
    
    print('[Audio] 📂 Queue loaded [${_context.name}] '
        '${songs.length} tracks, starting at $_currentIndex (shuffle: ${_shuffleMode == AudioServiceShuffleMode.all})');
    await _playSong(_queue[_currentIndex]);

    // FLOW 1: Trigger recommendation engine to fetch similar tracks upfront
    if (_context == PlaybackContext.search) {
      _fetchAndAppendAlgorithmSongs(_queue[_currentIndex]);
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
      final url = song.previewUrl;
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
        final url = song.previewUrl;
        if (url != null) {
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
      
      final url = song.previewUrl;
      if (url != null && url.isNotEmpty) {
        if (!url.startsWith('http')) {
          // Local file - instant loading
          await _audioPlayer.setAudioSource(AudioSource.uri(Uri.file(url)));
          await _audioPlayer.load();
        } else {
          try {
            // Network stream - optimized for sync
            await _audioPlayer.setAudioSource(LockCachingAudioSource(Uri.parse(url)));
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
    try {
      print('[Audio] 🎵 ── Loading: "${song.title}" by ${song.artist} ──');

      // Emit full Song (with previewUrl) so sync can use it
      _currentSongController.add(song);

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

      // Properly dispose and reset player to avoid "already exists" error
      await _audioPlayer.stop();
      
      // Clear any existing source completely
      try {
        await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse('about:blank')));
        await Future.delayed(const Duration(milliseconds: 100)); // Brief pause to ensure cleanup
      } catch (_) {
        // Ignore cleanup errors
      }

      final audioUrl = song.previewUrl;

      if (audioUrl != null && audioUrl.isNotEmpty) {
        try {
          // Local file path (from on_audio_query) — use file URI directly
          if (!audioUrl.startsWith('http')) {
            print('[Audio] 📁 Playing local file: $audioUrl');
            await _audioPlayer.setAudioSource(AudioSource.uri(Uri.file(audioUrl)));
            // Preload for faster start
            await _audioPlayer.load();
            await _audioPlayer.play();
            print('[Audio] ✅ Local file playback started');
            return;
          }

          print('[Audio] ▶️ Using LockCachingAudioSource with direct URL...');
          final source = LockCachingAudioSource(Uri.parse(audioUrl));
          await _audioPlayer.setAudioSource(source);
          // Enhanced preloading for faster start and better sync
          await _audioPlayer.load();
          
          // Wait for buffering to complete for network streams
          int bufferRetries = 0;
          while (bufferRetries < 5 && _audioPlayer.processingState == ProcessingState.loading) {
            await Future.delayed(const Duration(milliseconds: 100));
            bufferRetries++;
          }
          
          await _audioPlayer.play();
          print('[Audio] ✅ Playback started successfully!');
          return;
        } catch (e) {
          print('[Audio] ❌ Primary source failed: $e');
          try {
            print('[Audio] 🔄 Trying direct setUrl...');
            await _audioPlayer.setUrl(audioUrl);
            await _audioPlayer.play();
            print('[Audio] ✅ Direct URL playback started');
            return;
          } catch (e2) {
            print('[Audio] ❌ Direct URL also failed: $e2');
          }
        }
      } else {
        print('[Audio] ⚠️ No audio URL found for this song');
      }

      print('[Audio] ⚠️ Falling back to SoundHelix...');
      await _playFallback();
    } catch (e) {
      print('[Audio] ❌ Critical error in _playSong: $e');
      await _playFallback();
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

  Future<void> _playFallback() async {
    try {
      print('[Audio] 🔄 Playing fallback audio (SoundHelix)...');
      await _audioPlayer.setUrl('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3');
      await _audioPlayer.play();
    } catch (e) {
      print('[Audio] ❌ Even fallback failed: $e');
    }
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
  @override
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

  Future<void> skipToNext() async {
    try {
      print('[Audio] ⏭️ Skip to next requested');
      if (_queue.isEmpty) return;

      if (_currentIndex < _queue.length - 1) {
        // Normal advance — works for both sequential and pre-shuffled queues
        _currentIndex++;
        // Ensure song details match by emitting before playing
        _currentSongController.add(_queue[_currentIndex]);
        await _playSong(_queue[_currentIndex]);
      } else if (_repeatMode == AudioServiceRepeatMode.all) {
        // Wrap to beginning
        _currentIndex = 0;
        _currentSongController.add(_queue[_currentIndex]);
        await _playSong(_queue[_currentIndex]);
      } else {
        // No next song available -> Play a random algorithmic song
        _playNextAlgorithmSong();
      }
    } catch (e) {
      print('[Audio] ❌ Skip next error: $e');
    }
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      print('[Audio] ⏮️ Skip to previous requested');
      if (_queue.isEmpty) return;

      if (_audioPlayer.position.inSeconds > 3) {
        await _audioPlayer.seek(Duration.zero);
      } else if (_currentIndex > 0) {
        _currentIndex--;
        // Ensure song details match by emitting before playing
        _currentSongController.add(_queue[_currentIndex]);
        await _playSong(_queue[_currentIndex]);
      } else if (_repeatMode == AudioServiceRepeatMode.all) {
        _currentIndex = _queue.length - 1;
        _currentSongController.add(_queue[_currentIndex]);
        await _playSong(_queue[_currentIndex]);
      } else {
        // No previous song available -> Play a random algorithmic song
        _playNextAlgorithmSong();
      }
    } catch (e) { 
      print('[Audio] ❌ Skip previous error: $e'); 
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

  Future<void> _playNextAlgorithmSong() async {
    // Guard: never run for local files
    if (_context == PlaybackContext.local) return;

    final seedSong = _queue.isNotEmpty ? _queue[_currentIndex] : null;
    if (seedSong == null) return;

    try {
      print('[ML Algorithm] 🤖 Generating AI-powered recommendations...');
      print('[Phase 1] 🎵 Ingestion & Analysis - Extracting audio features');
      print('[Phase 2] 📊 Data Aggregation - Analyzing patterns');
      print('[Phase 3] 🧠 ML Engine - Matrix factorization & Cosine similarity');
      print('[Phase 4] 🚀 Queue Delivery - Optimizing recommendations');

      // Use ML Recommendation Engine (4-phase pipeline)
      final recommendations = await _mlEngine.deliverRecommendations(
        seedSong: seedSong,
        limit: 20,
      );

      if (recommendations.isNotEmpty) {
        print('[ML Algorithm] ✅ Generated ${recommendations.length} AI-powered recommendations');
        
        // Clear and update queue
        _queue.clear();
        _originalQueue.clear();
        _queue.addAll(recommendations);
        _originalQueue.addAll(recommendations);
        _currentIndex = 0;
        
        // Switch to radio context for continuous playback
        _context = PlaybackContext.radio;
        
        await _playSong(_queue[_currentIndex]);
        return;
      }
    } catch (e) {
      print('[ML Algorithm] ⚠️ ML engine failed: $e, falling back to basic algorithm');
    }

    // Fallback to basic algorithm if ML fails
    await _playNextAlgorithmSongFallback();
  }

  /// Fallback algorithm (original implementation)
  Future<void> _playNextAlgorithmSongFallback() async {
    const apiBase = 'https://jiosaavn-api-peach.vercel.app/api';
    final seedSong = _queue.isNotEmpty ? _queue[_currentIndex] : null;
    if (seedSong == null) return;

    // Quick title-based check to skip short remakes
    bool isTrendingVersion(Map<String, dynamic> r) {
      final t = '${r['name'] ?? ''} ${r['album']?['name'] ?? ''}'.toLowerCase();
      return t.contains('trending version') ||
          t.contains('trending remake') ||
          t.contains('speed up') ||
          t.contains('sped up') ||
          t.contains('slowed reverb') ||
          t.contains('lofi version') ||
          t.contains('short version');
    }

    try {
      print('[Algorithm] 🧠 Finding fallback tracks based on: "${seedSong.title}"');

      final primaryArtist = seedSong.artist.split(',').first.trim();
      // Search for the artist to create an "Artist Radio" experience
      final query = primaryArtist;

      for (final base in [apiBase, 'https://saavn.dev/api']) {
        try {
          final response = await _dio.get(
            '$base/search/songs',
            queryParameters: {'query': query, 'limit': 40, 'page': 1},
          );
          if (response.data?['success'] == true) {
            final results = response.data['data']?['results'] as List? ?? [];
            final newSongs = results
                .whereType<Map<String, dynamic>>()
                .where((r) => !isTrendingVersion(r))
                .map((r) => _parseSong(r))
                .where((s) =>
                    s.previewUrl != null &&
                    s.previewUrl!.isNotEmpty &&
                    (s.duration.inSeconds == 0 || s.duration.inSeconds >= 90))
                .where((s) => !_isDuplicateSong(s))
                .toList();
            if (newSongs.isNotEmpty) {
              print('[Algorithm] ✅ Pushing ${newSongs.length} recommended tracks to queue.');
              
              // Clear active_queue and original_queue
              _queue.clear();
              _originalQueue.clear();
              
              // Push recommended tracks into active_queue
              _queue.addAll(newSongs);
              _originalQueue.addAll(newSongs);
              
              // Set current_index to 0
              _currentIndex = 0;
              
              // Switch context to radio so subsequent ends also autoplay
              _context = PlaybackContext.radio;
              await _playSong(_queue[_currentIndex]);
              return;
            }
          }
        } catch (_) {}
      }

      for (final base in [apiBase, 'https://saavn.dev/api']) {
        try {
          final trending = await _dio.get(
            '$base/search/songs',
            queryParameters: {'query': 'latest hits', 'limit': 40},
          );
          if (trending.data?['success'] == true) {
            final results = trending.data['data']?['results'] as List? ?? [];
            if (results.isNotEmpty) {
              final newSongs = results
                  .whereType<Map<String, dynamic>>()
                  .map((r) => _parseSong(r))
                  .where((s) => s.previewUrl != null && s.previewUrl!.isNotEmpty)
                  .toList();
                  
              if (newSongs.isNotEmpty) {
                newSongs.shuffle(); // Shuffle the fallback so it doesn't always play the exact same sequence
                print('[Algorithm] ⚠️ API failed, pushed ${newSongs.length} trending fallbacks.');
                
                _queue.clear();
                _originalQueue.clear();
                _queue.addAll(newSongs);
                _originalQueue.addAll(newSongs);
                _currentIndex = 0;
                _context = PlaybackContext.radio;
                await _playSong(_queue[_currentIndex]);
                return;
              }
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      print('[Algorithm] ❌ Failed to fetch: $e');
    }
  }

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

  @override
  Future<void> onTaskRemoved() async {
    // Override to prevent stopping when app is removed from recent apps
    // This helps maintain playback during AOD and background usage
    print('[Audio] 📱 Task removed - maintaining background playback');
  }

  void dispose() {
    _currentSongController.close();
    _dio.close();
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
