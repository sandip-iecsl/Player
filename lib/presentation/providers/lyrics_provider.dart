import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';
import '../../domain/entities/lyrics_data.dart';
import '../../data/services/lyrics_service.dart';

final lyricsProvider = FutureProvider.family<LyricsData?, Song>((ref, song) async {
  return await lyricsService.fetchLyrics(song.title, song.artist, duration: song.duration);
});
