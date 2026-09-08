import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../data/models/song_model.dart';
import '../search_engine_provider.dart';
import '../search_tier.dart';

/// Tier 3: Absolute Fail-Safe / 100% Offline Client-Side Search Engine
/// 
/// Runs directly on device CPU hardware over locally synced Hive/SQLite boxes.
/// Uses a custom string distance (Levenshtein + Token Overlap + Substring Boost)
/// fuzzy matching algorithm with 0 cloud dependencies and 0 cost.
class ClientSideFuzzySearchProvider implements ISearchEngineProvider {
  @override
  String get providerName => 'Client-Side Fuzzy Engine (Tier 3 Offline)';

  @override
  SearchTier get tier => SearchTier.tier3LocalFailsafe;

  final List<String> _targetBoxes;

  ClientSideFuzzySearchProvider({
    List<String>? targetBoxes,
  }) : _targetBoxes = targetBoxes ??
            const [
              'offline_songs',
              'recentlyPlayed',
              'userPlaylists',
              'favorite_songs',
            ];

  @override
  Future<List<SongModel>> search(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final localSongs = await _collectAllLocalSongs();
    if (localSongs.isEmpty) return [];

    // Deduplicate songs by ID
    final uniqueMap = <String, SongModel>{};
    for (final song in localSongs) {
      if (song.id.isNotEmpty && !uniqueMap.containsKey(song.id)) {
        uniqueMap[song.id] = song;
      }
    }

    final scoredItems = <_ScoredSong>[];
    final queryTokens = cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    for (final song in uniqueMap.values) {
      final score = _calculateFuzzyScore(
        query: cleanQuery,
        queryTokens: queryTokens,
        title: song.title.toLowerCase(),
        artist: song.artist.toLowerCase(),
        album: (song.album ?? '').toLowerCase(),
      );

      if (score > 0.15) {
        scoredItems.add(_ScoredSong(song: song, score: score));
      }
    }

    // Sort descending by score
    scoredItems.sort((a, b) => b.score.compareTo(a.score));

    final results = scoredItems.map((e) => e.song).take(30).toList();
    debugPrint('[$providerName] ⚡ Found ${results.length} local fuzzy results for "$query"');
    return results;
  }

  /// Collects local songs across all active Hive boxes
  Future<List<SongModel>> _collectAllLocalSongs() async {
    final collected = <SongModel>[];

    for (final boxName in _targetBoxes) {
      try {
        if (!Hive.isBoxOpen(boxName)) {
          // Attempt to open if not already open
          try {
            await Hive.openBox(boxName);
          } catch (_) {
            continue;
          }
        }

        final box = Hive.box(boxName);
        for (var i = 0; i < box.length; i++) {
          final dynamic val = box.getAt(i);
          if (val == null) continue;

          if (val is Map) {
            try {
              collected.add(SongModel.fromJson(Map<String, dynamic>.from(val)));
            } catch (_) {}
          } else if (val is String) {
            try {
              final decoded = jsonDecode(val);
              if (decoded is Map<String, dynamic>) {
                // If playlist wrapper containing 'songs' array
                if (decoded.containsKey('songs') && decoded['songs'] is List) {
                  for (final item in decoded['songs']) {
                    if (item is Map<String, dynamic>) {
                      collected.add(SongModel.fromJson(item));
                    }
                  }
                } else {
                  collected.add(SongModel.fromJson(decoded));
                }
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('[$providerName] Notice: Could not read box $boxName: $e');
      }
    }

    return collected;
  }

  /// Calculates composite fuzzy match score between [0.0 and 1.0]
  double _calculateFuzzyScore({
    required String query,
    required List<String> queryTokens,
    required String title,
    required String artist,
    required String album,
  }) {
    // 1. Exact match boosts
    if (title == query) return 1.0;
    if (title.startsWith(query)) return 0.95;
    if (artist == query) return 0.90;
    if (artist.startsWith(query)) return 0.85;

    // 2. Substring inclusion
    if (title.contains(query)) return 0.80;
    if (artist.contains(query)) return 0.70;
    if (album.contains(query)) return 0.60;

    // 3. Token-based overlap scoring
    double tokenScore = 0.0;
    final allContent = '$title $artist $album';
    int matchedTokens = 0;

    for (final qToken in queryTokens) {
      if (allContent.contains(qToken)) {
        matchedTokens++;
      } else {
        // Levenshtein check on individual words
        final words = allContent.split(RegExp(r'\s+'));
        for (final word in words) {
          final distance = _levenshteinDistance(qToken, word);
          final maxLen = max(qToken.length, word.length);
          if (maxLen > 0 && distance <= 2) {
            final sim = 1.0 - (distance / maxLen);
            if (sim > 0.7) {
              matchedTokens++;
              break;
            }
          }
        }
      }
    }

    if (queryTokens.isNotEmpty) {
      tokenScore = (matchedTokens / queryTokens.length) * 0.75;
    }

    // 4. Overall Levenshtein similarity against title
    final titleSim = _stringSimilarity(query, title);
    final artistSim = _stringSimilarity(query, artist);

    return max(tokenScore, max(titleSim * 0.7, artistSim * 0.6));
  }

  /// Computes normalized similarity between two strings [0.0 - 1.0]
  double _stringSimilarity(String s1, String s2) {
    if (s1.isEmpty && s2.isEmpty) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    final distance = _levenshteinDistance(s1, s2);
    final maxLen = max(s1.length, s2.length);
    return 1.0 - (distance / maxLen);
  }

  /// Classic Levenshtein Distance Matrix Algorithm
  int _levenshteinDistance(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.filled(t.length + 1, 0);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i <= t.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < t.length; j++) {
        final cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }

      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[t.length];
  }

  @override
  Future<bool> isHealthy() async => true;
}

class _ScoredSong {
  final SongModel song;
  final double score;

  const _ScoredSong({required this.song, required this.score});
}
