import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/audio_service.dart';
import '../../domain/entities/song.dart';

final audioServiceProvider = Provider<AudioServiceHandler>((ref) {
  return audioHandler;
});

// Stream the current song directly from the audio handler's queue
// This preserves previewUrl which is needed for sync
final currentSongProvider = StreamProvider<Song?>((ref) {
  final handler = ref.watch(audioServiceProvider);
  return handler.currentSongStream;
});

final isPlayingProvider = StreamProvider<bool>((ref) {
  return ref.watch(audioServiceProvider).playingStream;
});

final currentPositionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(audioServiceProvider).positionStream;
});

final currentDurationProvider = StreamProvider<Duration?>((ref) {
  return ref.watch(audioServiceProvider).durationStream;
});

final queueProvider = StateProvider<List<Song>>((ref) => []);
final currentQueueIndexProvider = StateProvider<int>((ref) => 0);

