import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';
import '../../data/services/hybrid_search_service.dart';
import '../../data/services/spotify_client_service.dart';
import '../../data/services/local_taste_engine.dart';
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
  final results = await service.searchSongs(query, limit: 30);
  
  if (results.isEmpty) return results;

  final lowerQuery = query.toLowerCase().trim();
  
  final tasteEngine = LocalTasteEngine();
  tasteEngine.init();
  final dummySeed = Song(id: '', title: '', artist: '', duration: Duration.zero);

  // Sort exact matches to the top, and personalize the rest using taste engine affinity
  results.sort((a, b) {
    final aExactTitle = a.title.toLowerCase() == lowerQuery;
    final bExactTitle = b.title.toLowerCase() == lowerQuery;
    
    if (aExactTitle && !bExactTitle) return -1;
    if (!aExactTitle && bExactTitle) return 1;
    
    final aExactArtist = a.artist.toLowerCase() == lowerQuery;
    final bExactArtist = b.artist.toLowerCase() == lowerQuery;
    
    if (aExactArtist && !bExactArtist) return -1;
    if (!aExactArtist && bExactArtist) return 1;
    
    // Fallback: Sort by user's personalized affinity score
    final aScore = tasteEngine.getAffinityScore(dummySeed, a);
    final bScore = tasteEngine.getAffinityScore(dummySeed, b);
    return bScore.compareTo(aScore);
  });

  return results;
});

final autocompleteSuggestionsProvider = FutureProvider.family<Map<String, List<dynamic>>, String>((ref, query) async {
  if (query.trim().isEmpty) return {};
  final service = ref.read(hybridSearchServiceProvider);
  return service.getAutocomplete(query);
});

// ─── Home Screen Sections ─────────────────────────────────────────────────────

List<Song> filterDashboardSongs(List<Song> songs) {
  return songs.where((s) {
    final text = '${s.title} ${s.artist}'.toLowerCase();
    if (text.contains('michael jackson') || 
        text.contains('michel jacson') || 
        text.contains('english rap') || 
        text.contains('pista')) {
      return false;
    }
    return true;
  }).toList();
}

final trendingMusicProvider = FutureProvider<List<Song>>((ref) async {
  final service = ref.read(hybridSearchServiceProvider);
  final songs = await service.getTrendingTracks(limit: 30);
  return filterDashboardSongs(songs).take(20).toList();
});

final hitsHindiProvider = FutureProvider<List<Song>>((ref) async {
  final service = ref.read(hybridSearchServiceProvider);
  final songs = await service.getTracksByGenre('bollywood', limit: 30);
  return filterDashboardSongs(songs).take(20).toList();
});

final personalizedRecommendationsProvider = FutureProvider<List<Song>>((ref) async {
  final service      = ref.read(hybridSearchServiceProvider);
  final tasteEngine  = LocalTasteEngine();
  tasteEngine.init();

  // Pull top artists from local Hive history
  final artistHistory = tasteEngine.getTopArtists(limit: 5);

  List<Song> candidates = [];

  if (artistHistory.isNotEmpty) {
    // Build a pool from top artists (2-3 songs each)
    for (final artist in artistHistory.take(3)) {
      try {
        final songs = await service.searchSongs(artist, limit: 8);
        candidates.addAll(songs);
      } catch (_) {}
    }
  }

  if (candidates.length < 10) {
    // Supplement with trending if pool is thin
    try {
      final trending = await service.getTrendingTracks(limit: 20);
      candidates.addAll(trending);
    } catch (_) {}
  }

  if (candidates.isEmpty) return [];

  // Deduplicate by song ID
  final seen = <String>{};
  candidates = candidates.where((s) => seen.add(s.id)).toList();

  // Score and sort by user affinity
  final recentlyPlayed = ref.read(recentlyPlayedProvider);
  final seed = recentlyPlayed.isNotEmpty ? recentlyPlayed.first : candidates.first;

  candidates.sort((a, b) {
    final aScore = tasteEngine.getAffinityScore(seed, a);
    final bScore = tasteEngine.getAffinityScore(seed, b);
    return bScore.compareTo(aScore);
  });

  return filterDashboardSongs(candidates).take(20).toList();
});


final todaysBiggestHitsProvider = FutureProvider<List<Song>>((ref) async {
  final service = ref.read(hybridSearchServiceProvider);
  final songs = await service.getTracksByGenre('pop', limit: 30);
  return filterDashboardSongs(songs).take(20).toList();
});

final newReleasesProvider = FutureProvider<List<Song>>((ref) async {
  final service = ref.read(hybridSearchServiceProvider);
  final songs = await service.searchSongs('new releases 2025', limit: 30);
  return filterDashboardSongs(songs).take(20).toList();
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

// Personalized recommendations based on recently played — uses Spotify + Local Taste Engine
final personalizedFromHistoryProvider = FutureProvider<List<Song>>((ref) async {
  final recentlyPlayed = ref.watch(recentlyPlayedProvider);
  final service = ref.read(hybridSearchServiceProvider);
  
  final tasteEngine = LocalTasteEngine();
  tasteEngine.init();
  
  List<Song> candidates;
  if (recentlyPlayed.isEmpty) {
    // No history yet — fall back to trending
    candidates = await service.getTrendingTracks(limit: 25);
  } else {
    // Use the most recently played song as seed
    final seedSong = recentlyPlayed.first;
    final recs = await service.getRecommendations(seedSong, limit: 25);
    if (recs.isNotEmpty) {
      candidates = recs;
    } else {
      // Fallback: search by primary artist only (take first name before comma)
      final primaryArtist = seedSong.artist.split(',').first.trim();
      candidates = await service.searchSongs(primaryArtist, limit: 25);
    }
  }

  
  if (candidates.isEmpty) return [];

  // Sort and filter candidates using user taste engine affinity score
  final scoredCandidates = candidates.map((song) {
    final seedSong = recentlyPlayed.isNotEmpty ? recentlyPlayed.first : candidates.first;
    final score = tasteEngine.getAffinityScore(seedSong, song);
    return MapEntry(song, score);
  }).toList();
  
  scoredCandidates.sort((a, b) => b.value.compareTo(a.value));
  final sortedSongs = scoredCandidates.map((e) => e.key).toList();
  return filterDashboardSongs(sortedSongs).take(20).toList();
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

final multipleArtistsTopTracksProvider = FutureProvider.family<List<Song>, String>((ref, joinedArtists) async {
  final artists = joinedArtists.split('|');
  final service = ref.read(hybridSearchServiceProvider);
  final List<Song> allSongs = [];
  
  final futures = artists.map((artist) => service.getArtistTopTracks(artist, limit: 15));
  final results = await Future.wait(futures);
  
  for (var result in results) {
    allSongs.addAll(result);
  }
  
  final uniqueSongs = <String, Song>{};
  for (var song in allSongs) {
    uniqueSongs[song.id] = song;
  }
  
  final finalList = uniqueSongs.values.toList();
  finalList.shuffle();
  return finalList;
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
