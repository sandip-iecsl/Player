import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';
import '../../data/services/hybrid_search_service.dart';
import '../../data/services/spotify_client_service.dart';
import 'history_provider.dart';

// ─── Core Services ────────────────────────────────────────────────────────────

final hybridSearchServiceProvider = Provider<HybridSearchService>((ref) {
  final service = HybridSearchService();
  ref.onDispose(() => service.dispose());
  return service;
});

final spotifyServiceProvider = Provider<SpotifyClientService>((ref) {
  final service = SpotifyClientService();
  ref.onDispose(() => service.dispose());
  return service;
});

// ─── Search ───────────────────────────────────────────────────────────────────

final searchSongsProvider = FutureProvider.family<List<Song>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];
  final service = ref.read(hybridSearchServiceProvider);
  return service.searchSongs(query, limit: 20);
});

// ─── Home Screen Sections ─────────────────────────────────────────────────────

final trendingMusicProvider = FutureProvider<List<Song>>((ref) async {
  final service = ref.read(hybridSearchServiceProvider);
  return service.getTrendingTracks(limit: 20);
});

final hitsHindiProvider = FutureProvider<List<Song>>((ref) async {
  final service = ref.read(hybridSearchServiceProvider);
  return service.getTracksByGenre('bollywood', limit: 20);
});

final personalizedRecommendationsProvider = FutureProvider<List<Song>>((ref) async {
  final service = ref.read(hybridSearchServiceProvider);
  return service.getTrendingTracks(limit: 20);
});

final todaysBiggestHitsProvider = FutureProvider<List<Song>>((ref) async {
  final service = ref.read(hybridSearchServiceProvider);
  return service.getTracksByGenre('pop', limit: 20);
});

final newReleasesProvider = FutureProvider<List<Song>>((ref) async {
  final service = ref.read(hybridSearchServiceProvider);
  return service.searchSongs('new releases 2025', limit: 20);
});

// ─── Spotify Browse ───────────────────────────────────────────────────────────

final featuredPlaylistsProvider = FutureProvider<List<SpotifyPlaylist>>((ref) async {
  final spotify = ref.read(spotifyServiceProvider);
  return spotify.getFeaturedPlaylists(limit: 20);
});

final spotifyCategoriesProvider = FutureProvider<List<SpotifyCategory>>((ref) async {
  final spotify = ref.read(spotifyServiceProvider);
  return spotify.getCategories(limit: 20);
});

final categoryPlaylistsProvider = FutureProvider.family<List<SpotifyPlaylist>, String>((ref, categoryId) async {
  final spotify = ref.read(spotifyServiceProvider);
  return spotify.getCategoryPlaylists(categoryId, limit: 20);
});

// Fetch tracks from a Spotify playlist and resolve to playable songs
final playlistSongsProvider = FutureProvider.family<List<Song>, String>((ref, playlistId) async {
  final spotify = ref.read(spotifyServiceProvider);
  final hybrid  = ref.read(hybridSearchServiceProvider);
  final tracks  = await spotify.getPlaylistTracks(playlistId, limit: 50);
  if (tracks.isEmpty) return [];
  // Resolve to JioSaavn stream URLs
  final songs = <Song>[];
  for (final t in tracks.take(20)) {
    final results = await hybrid.searchSongs('${t.title} ${t.artist}', limit: 1);
    if (results.isNotEmpty) songs.add(results.first);
    if (songs.length >= 20) break;
  }
  return songs;
});

// Personalized recommendations based on recently played — uses Spotify
final personalizedFromHistoryProvider = FutureProvider<List<Song>>((ref) async {
  final recentlyPlayed = ref.watch(recentlyPlayedProvider);
  if (recentlyPlayed.isEmpty) {
    // No history yet — fall back to trending
    final service = ref.read(hybridSearchServiceProvider);
    return service.getTrendingTracks(limit: 20);
  }

  // Use the most recently played song as seed
  final seedSong = recentlyPlayed.first;
  final service = ref.read(hybridSearchServiceProvider);
  final recs = await service.getRecommendations(seedSong, limit: 20);
  if (recs.isNotEmpty) return recs;

  // Fallback: search by the artist of the most played song
  return service.searchSongs(seedSong.artist, limit: 20);
});

// ─── Recommendations ──────────────────────────────────────────────────────────

final songRecommendationsProvider = FutureProvider.family<List<Song>, Song>((ref, song) async {
  final service = ref.read(hybridSearchServiceProvider);
  return service.getRecommendations(song, limit: 20);
});

final artistTopTracksProvider = FutureProvider.family<List<Song>, String>((ref, artistName) async {
  final service = ref.read(hybridSearchServiceProvider);
  return service.getArtistTopTracks(artistName, limit: 20);
});

// ─── Genre ────────────────────────────────────────────────────────────────────

final genreSongsProvider = FutureProvider.family<List<Song>, String>((ref, genre) async {
  final service = ref.read(hybridSearchServiceProvider);
  return service.getTracksByGenre(genre, limit: 20);
});

// ─── Helpers ──────────────────────────────────────────────────────────────────

void invalidateAllMusicProviders(WidgetRef ref) {
  ref.invalidate(trendingMusicProvider);
  ref.invalidate(hitsHindiProvider);
  ref.invalidate(personalizedRecommendationsProvider);
  ref.invalidate(personalizedFromHistoryProvider);
  ref.invalidate(todaysBiggestHitsProvider);
  ref.invalidate(newReleasesProvider);
  ref.invalidate(featuredPlaylistsProvider);
  ref.invalidate(spotifyCategoriesProvider);
}
