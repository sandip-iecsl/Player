import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';
import '../providers/audio_provider.dart';

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
  Timer? _playbackTimer;
  Song? _currentSong;
  DateTime? _songStartTime;

  AuraNotifier(this._ref) : super(AuraState(sessionVector: List.filled(12, 0.5), currentEngagementTime: Duration.zero)) {
    _initHeartbeat();
    _listenToPlayback();
  }

  void _initHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
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
      // Hard Skip: Negative Vector Shift
      _applyVectorShift(song, -0.2);
      print('[Aura-Engine] ⚠️ Hard Skip detected (<10s). Negative shift applied.');
    } else if (duration.inSeconds > 90) {
      // Deep Listen: Re-center toward this track
      _applyVectorShift(song, 0.1);
      print('[Aura-Engine] ✨ Deep Listen detected (>90s). Re-centering session vector.');
    }
  }

  void _applyVectorShift(Song song, double weight) {
    // In a real scenario, we'd fetch the DNA for this song. 
    // Here we simulate with a dummy vector or derived from metadata
    final List<double> songVector = List.filled(12, 0.5); 
    
    final newVector = List<double>.generate(12, (i) {
      return (state.sessionVector[i] + (songVector[i] * weight)).clamp(0.0, 1.0);
    });
    
    state = state.copyWith(sessionVector: newVector);
  }

  void _sendHeartbeat() {
    if (_currentSong == null) return;
    
    final engagementSeconds = _songStartTime != null 
        ? DateTime.now().difference(_songStartTime!).inSeconds 
        : 0;

    // Simulation of pinging backend
    print('[Aura-Heartbeat] 💓 Ping: Engaged with "${_currentSong!.title}" for ${engagementSeconds}s. Vector: ${state.sessionVector.map((v) => v.toStringAsFixed(2)).toList()}');
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _playbackTimer?.cancel();
    super.dispose();
  }
}
