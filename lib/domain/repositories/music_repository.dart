import '../entities/song.dart';

abstract class MusicRepository {
  Future<List<Song>> getTrendingMusic();
  Future<List<Song>> getGlobalCharts();
  Future<List<Song>> getNewReleases();
  Future<List<Map<String, dynamic>>> getTopArtists();
  Future<List<Song>> searchSongs(String query);
  Future<List<Song>> getRecommendations();
  Future<List<Song>> getHitsHindi();

  // Vibe-specific sections
  Future<List<Song>> getTodaysBiggestHits();
  Future<List<Song>> getRecommendedForYou(List<String> genreHints);
  Future<List<Song>> getLofiChillTracks();
  Future<List<Song>> getDeepFocusTracks();
  Future<List<Song>> getLateNightVibeTracks();
}
