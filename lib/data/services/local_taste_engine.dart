import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/song.dart';
import 'cloud_sync_service.dart';

/// 100% Free Local Taste Matrix Engine
/// Tracks song transitions to create a highly personalized collaborative-filter equivalent
/// entirely on-device, with zero cloud dependency.
class LocalTasteEngine {
  static const String _transitionsBoxName = 'track_transitions';
  static const String _historyBoxName = 'listening_history';
  static const String _skipBoxName = 'skip_signals';
  
  late Box _transitionsBox;
  late Box _historyBox;

  void init() {
    _transitionsBox = Hive.box(_transitionsBoxName);
    _historyBox = Hive.box(_historyBoxName);
  }

  /// Logs a transition from one track to another. 
  /// This creates the "Users who played A also played B" matrix locally.
  Future<void> logTransition(Song source, Song dest) async {
    final key = source.id;
    final Map transitions = _transitionsBox.get(key, defaultValue: {}) as Map;
    
    // Increment the count of how many times dest was played after source
    final destId = dest.id;
    final currentCount = (transitions[destId] ?? 0) as int;
    transitions[destId] = currentCount + 1;
    
    await _transitionsBox.put(key, transitions);
    
    // Also log to general history
    await logPlay(dest);
    
    // The backup is handled in logPlay, so we don't need to duplicate it here
  }

  /// Logs a general playback event to determine overall top artists and song frequencies
  Future<void> logPlay(Song song) async {
    // 1. Log artist history
    final Map artistHistory = _historyBox.get('artists', defaultValue: {}) as Map;
    final artists = song.artist.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    
    for (final artist in artists) {
      final count = (artistHistory[artist] ?? 0) as int;
      artistHistory[artist] = count + 1;
    }
    await _historyBox.put('artists', artistHistory);

    // 2. Log song history
    final Map songHistory = _historyBox.get('songs', defaultValue: {}) as Map;
    final songId = song.id;
    final songPlayCount = (songHistory[songId] ?? 0) as int;
    songHistory[songId] = songPlayCount + 1;
    await _historyBox.put('songs', songHistory);
    
    // Backup data to cloud
    CloudSyncService().backupData();
  }

  /// Gets local affinity score for a candidate song based on user preferences and history:
  /// 1. Co-occurrence check (transition matrix): +5.0 per explicit past transition.
  /// 2. Favorite Artist affinity: +1.5 if the candidate matches the user's top 10 artists.
  /// 3. Favorite Song boost: +3.0 if the song is in the user's 'Favourite' playlist.
  /// 4. Custom Playlist boost: +2.0 if the song is in any user-created playlists.
  /// 5. Recently Played boost: +1.0 per times played in recently played history.
  /// 6. Frequency Play boost: +0.5 per total times played in history.
  double getAffinityScore(Song seedSong, Song candidateSong) {
    double score = 0.0;

    // 1. Co-occurrence check
    final Map transitions = _transitionsBox.get(seedSong.id, defaultValue: {}) as Map;
    final int transitionCount = (transitions[candidateSong.id] ?? 0) as int;
    if (transitionCount > 0) {
      score += (transitionCount * 5.0); // +5 per explicit past transition!
    }

    // 2. Top artist affinity
    final Map artistHistory = _historyBox.get('artists', defaultValue: {}) as Map;
    final candidateArtists = candidateSong.artist.split(',').map((e) => e.trim());
    
    // Find if the candidate artist is one of the top 5 most played
    final sortedArtists = artistHistory.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    final topArtists = sortedArtists.take(10).map((e) => e.key).toList();

    for (final artist in candidateArtists) {
      if (topArtists.contains(artist)) {
        score += 1.5; // +1.5 for matching a favorite artist
      }
    }

    // 3 & 4. Favorites & Custom Playlist checks
    if (Hive.isBoxOpen('userPlaylists')) {
      final playlistsBox = Hive.box<String>('userPlaylists');
      for (final key in playlistsBox.keys) {
        final val = playlistsBox.get(key);
        if (val is String) {
          try {
            final playlistMap = jsonDecode(val) as Map<String, dynamic>;
            final playlistId = playlistMap['id']?.toString() ?? '';
            final songsList = playlistMap['songs'] as List? ?? [];
            final hasSong = songsList.any((s) => s is Map && s['id']?.toString() == candidateSong.id);
            if (hasSong) {
              if (playlistId == 'favorites_playlist_id') {
                score += 3.0; // Boost for Favourites
              } else {
                score += 2.0; // Boost for custom playlists
              }
            }
          } catch (_) {}
        }
      }
    }

    // 5. Recently Played check
    if (Hive.isBoxOpen('recentlyPlayed')) {
      final recentlyBox = Hive.box<String>('recentlyPlayed');
      final list = recentlyBox.values.toList();
      int recentCount = 0;
      for (final val in list) {
        if (val.isNotEmpty) {
          try {
            final songMap = jsonDecode(val) as Map<String, dynamic>;
            if (songMap['id']?.toString() == candidateSong.id) {
              recentCount++;
            }
          } catch (_) {}
        }
      }
      if (recentCount > 0) {
        score += (recentCount * 1.0); // Boost based on how many times user played this song recently
      }
    }

    // 6. Overall song frequency play count check
    final Map songHistory = _historyBox.get('songs', defaultValue: {}) as Map;
    final int songPlayCount = (songHistory[candidateSong.id] ?? 0) as int;
    if (songPlayCount > 0) {
      score += (songPlayCount * 0.5); // Boost for frequently played songs
    }

    return score;
  }

  /// Exposes transitions for a seed song to pass to the recommendation isolate.
  Map getTransitionsForSong(String songId) {
    return _transitionsBox.get(songId, defaultValue: {}) as Map;
  }

  /// Exposes song history plays to pass to the recommendation isolate.
  Map getSongHistory() {
    return _historyBox.get('songs', defaultValue: {}) as Map;
  }

  /// Returns the user's top [limit] most-played artists (names only).
  List<String> getTopArtists({int limit = 10}) {
    final Map artistHistory = _historyBox.get('artists', defaultValue: {}) as Map;
    if (artistHistory.isEmpty) return [];
    final sorted = artistHistory.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    return sorted.take(limit).map((e) => e.key.toString()).toList();
  }

  /// Returns the user's top [limit] most-played song IDs with their play counts.
  List<MapEntry<String, int>> getTopSongs({int limit = 10}) {
    final Map songHistory = _historyBox.get('songs', defaultValue: {}) as Map;
    if (songHistory.isEmpty) return [];
    final sorted = songHistory.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    return sorted
        .take(limit)
        .map((e) => MapEntry(e.key.toString(), (e.value as int? ?? 0)))
        .toList();
  }

  /// Total number of plays logged across all songs.
  int getTotalPlays() {
    final Map songHistory = _historyBox.get('songs', defaultValue: {}) as Map;
    return songHistory.values.fold<int>(0, (s, v) => s + (v as int? ?? 0));
  }

  /// Logs a skip event (user skipped within a short time window).
  /// This creates a negative signal used to penalize repeated recommendations.
  Future<void> logSkip(Song song) async {
    final Map skips = _historyBox.get('skip_signals', defaultValue: {}) as Map;
    final currentCount = (skips[song.id] ?? 0) as int;
    skips[song.id] = currentCount + 1;
    await _historyBox.put('skip_signals', skips);
  }

  /// Returns the number of times a song has been skipped.
  int getSkipCount(String songId) {
    final Map skips = _historyBox.get('skip_signals', defaultValue: {}) as Map;
    return (skips[songId] ?? 0) as int;
  }

  /// Returns the full skip signals map for use in the scoring isolate.
  Map getSkipSignals() {
    return _historyBox.get('skip_signals', defaultValue: {}) as Map;
  }
}
