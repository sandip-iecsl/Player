import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';
import '../../data/services/lyrics_service.dart';

final lyricsProvider = FutureProvider.family<String?, Song>((ref, song) async {
  return await lyricsService.fetchLyrics(song.title, song.artist);
});
