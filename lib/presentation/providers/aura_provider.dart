import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';
import '../providers/audio_provider.dart';
import '../../data/services/local_taste_engine.dart';

final auraProvider = StateNotifierProvider<AuraNotifier, AuraState>((ref) {
  return AuraNotifier(ref);
});

class AuraState {
  final List<double> sessionVector;
  final Duration currentEngagementTime;

  AuraState({
    required this.sessionVector,
    required this.currentEngagementTime,
  });

  AuraState copyWith({
    List<double>? sessionVector,
    Duration? currentEngagementTime,
  }) {
    return AuraState(
      sessionVector: sessionVector ?? this.sessionVector,
      currentEngagementTime: currentEngagementTime ?? this.currentEngagementTime,
    );
  }
}

class AuraNotifier extends StateNotifier<AuraState> {
  final Ref _ref;
  Timer? _heartbeatTimer;
  Song? _currentSong;
  DateTime? _songStartTime;

  AuraNotifier(this._ref)
      : super(AuraState(
          sessionVector: List.filled(12, 0.5),
          currentEngagementTime: Duration.zero,
        )) {
    _initHeartbeat();
    _listenToPlayback();
  }

  void _initHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _sendHeartbeat();
    });
  }

  void _listenToPlayback() {
    _ref.listen(currentSongProvider, (previous, next) {
      final song = next.valueOrNull;
      if (song != null && song.id != _currentSong?.id) {
        _handleSongChange(song);
      }
    });
  }

  void _handleSongChange(Song newSong) {
    if (_currentSong != null && _songStartTime != null) {
      final duration = DateTime.now().difference(_songStartTime!);
      _processReinforcement(_currentSong!, duration);
    }
    _currentSong = newSong;
    _songStartTime = DateTime.now();
  }

  void _processReinforcement(Song song, Duration duration) {
    if (duration.inSeconds < 10) {
      // Hard Skip → negative reinforcement
      _applyVectorShift(song, -0.15);
      print('[Aura-Engine] ⚠️ Hard Skip (<10s). Negative shift applied for "${song.title}".');
    } else if (duration.inSeconds > 60) {
      // Good listen → positive reinforcement, stronger for longer listens
      final weight = duration.inSeconds > 180 ? 0.12 : 0.08;
      _applyVectorShift(song, weight);
      print('[Aura-Engine] ✨ Good Listen (${duration.inSeconds}s). Positive shift for "${song.title}".');
    }
    // 10-60s: neutral, no shift (user may have skipped or lost interest)
  }

  /// Derive a 12-dimensional DNA vector from song metadata.
  ///
  /// Dimensions:
  ///  0  Bollywood affinity       (keyword in album/artist)
  ///  1  Hindi language indicator (artist/album heuristic)
  ///  2  Pop/international        (english-language heuristic)
  ///  3  Romantic mood            (keywords: love, pyaar, dil, mohabbat)
  ///  4  Upbeat / party           (keywords: dance, party, dhoom, beats)
  ///  5  Melancholic / sad        (keywords: sad, tanha, dard, roke)
  ///  6  Artist familiarity       (has play history in LocalTasteEngine)
  ///  7  Song familiarity         (has been played before)
  ///  8  Duration normalised      (1.0 = 6 min+, 0.0 = <1 min)
  ///  9  Has album art            (0.0 = no art, 1.0 = has art)
  /// 10  Collaborative (many artists listed)
  /// 11  New artist (not in user history at all)
  List<double> _buildSongVector(Song song) {
    final titleL  = song.title.toLowerCase();
    final artistL = song.artist.toLowerCase();
    final albumL  = (song.album ?? '').toLowerCase();

    // ── Helper ───────────────────────────────────────────────────────────────
    bool any(String text, List<String> words) =>
        words.any((w) => text.contains(w));

    // ── Dim 0: Bollywood ─────────────────────────────────────────────────────
    final isBollywood = any(artistL, ['pritam', 'anu malik', 'a.r. rahman', 'shankar',
        'vishal-shekhar', 'tanishk', 'sachet', 'badshah', 'darshan',
        'arijit', 'jubin', 'neha kakkar', 'atif'])
        || any(albumL, ['bollywood', 'hindi', 'saavncdn']);
    final d0 = isBollywood ? 0.85 : 0.2;

    // ── Dim 1: Hindi language ─────────────────────────────────────────────────
    final isHindi = any(titleL, ['dil', 'pyaar', 'ishq', 'mohabbat', 'yaar', 'tere',
        'mere', 'teri', 'meri', 'jo', 'hai', 'nahi', 'koi', 'woh',
        'jab', 'kab', 'aaj', 'raat', 'dard']) || isBollywood;
    final d1 = isHindi ? 0.9 : 0.1;

    // ── Dim 2: Pop / International ────────────────────────────────────────────
    final isInternational = any(artistL, ['michael jackson', 'ariana', 'justin bieber',
        'selena', 'katy perry', 'ed sheeran', 'olivia rodrigo', 'taylor swift',
        'bruno mars', 'the weeknd', 'beyoncé', 'rihanna', 'dua lipa',
        'billie eilish', 'coldplay', 'shawn mendes', 'one direction'])
        || (!isHindi && !isBollywood);
    final d2 = isInternational ? 0.85 : 0.15;

    // ── Dim 3: Romantic ───────────────────────────────────────────────────────
    final isRomantic = any(titleL, ['love', 'pyaar', 'ishq', 'dil', 'mohabbat',
        'humsafar', 'tere bina', 'tumse', 'romance', 'kiss', 'heart']);
    final d3 = isRomantic ? 0.9 : 0.3;

    // ── Dim 4: Upbeat / Party ─────────────────────────────────────────────────
    final isUpbeat = any(titleL, ['dance', 'party', 'dhoom', 'beats', 'bass',
        'move', 'shake', 'jump', 'rave', 'club', 'nagada', 'hookup',
        'swag', 'rock', 'disco']);
    final d4 = isUpbeat ? 0.9 : 0.25;

    // ── Dim 5: Melancholic / Sad ──────────────────────────────────────────────
    final isSad = any(titleL, ['sad', 'tanha', 'dard', 'roke', 'aankhon', 'aansu',
        'rootha', 'roothna', 'judaa', 'broken', 'cry', 'tears', 'alone',
        'miss', 'bye', 'farewell', 'lo fi', 'lofi', 'chill evenings']);
    final d5 = isSad ? 0.85 : 0.2;

    // ── Dim 6: Artist familiarity (from history) ──────────────────────────────
    final tasteEngine = LocalTasteEngine();
    try { tasteEngine.init(); } catch (_) {}
    final topArtists = tasteEngine.getTopArtists(limit: 20);
    final primaryArtist = song.artist.split(',').first.trim().toLowerCase();
    final artistFamiliar = topArtists.any((a) => a.toLowerCase() == primaryArtist);
    final d6 = artistFamiliar ? 0.9 : 0.2;

    // ── Dim 7: Song familiarity (has been played before) ─────────────────────
    final topSongs = tasteEngine.getTopSongs(limit: 50);
    final songFamiliar = topSongs.any((e) => e.key == song.id);
    final d7 = songFamiliar ? 0.85 : 0.1;

    // ── Dim 8: Duration normalised ────────────────────────────────────────────
    final secs = song.duration.inSeconds.clamp(60, 360);
    final d8 = ((secs - 60) / 300).clamp(0.0, 1.0);

    // ── Dim 9: Has album art ──────────────────────────────────────────────────
    final d9 = (song.albumArt != null && song.albumArt!.isNotEmpty) ? 1.0 : 0.0;

    // ── Dim 10: Collaborative (many artists) ─────────────────────────────────
    final artistCount = song.artist.split(',').length;
    final d10 = (artistCount / 5.0).clamp(0.0, 1.0);

    // ── Dim 11: Brand-new artist (not in history at all) ─────────────────────
    final d11 = artistFamiliar ? 0.0 : 1.0;

    return [d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11];
  }

  void _applyVectorShift(Song song, double weight) {
    final songVector = _buildSongVector(song);
    final newVector = List<double>.generate(12, (i) {
      return (state.sessionVector[i] + (songVector[i] - state.sessionVector[i]) * weight)
          .clamp(0.0, 1.0);
    });
    state = state.copyWith(sessionVector: newVector);
  }

  void _sendHeartbeat() {
    if (_currentSong == null) return;
    final engagementSeconds = _songStartTime != null
        ? DateTime.now().difference(_songStartTime!).inSeconds
        : 0;
    print('[Aura-Heartbeat] 💓 Ping: Engaged with "${_currentSong!.title}" for ${engagementSeconds}s.'
        ' Vector: ${state.sessionVector.map((v) => v.toStringAsFixed(2)).toList()}');
  }

  /// Expose the current session vector so the recommendation engine can use it.
  List<double> get sessionVector => state.sessionVector;

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}
