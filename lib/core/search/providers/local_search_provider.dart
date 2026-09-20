import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../domain/entities/song.dart';
import '../models/search_models.dart';
import '../ranking/string_similarity.dart';
import 'provider_health.dart';
import 'search_provider.dart';

/// Provider 1 & 9: Local Hive Cache, Downloaded Songs, Playlists & Local Fuzzy Fallback
class LocalSearchProvider implements SearchProviderClient {
  @override
  final SearchProviderType provider = SearchProviderType.local;

  @override
  final ProviderHealth health = ProviderHealth(provider: SearchProviderType.local);

  @override
  bool get isEnabled => true;

  @override
  int get priority => 1;

  @override
  Duration get timeout => const Duration(milliseconds: 500);

  @override
  Future<List<SearchCandidate>> search(
    ParsedQuery query,
    SearchRequest request,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final allLocalSongs = <String, Song>{};

      // 1. Check offline downloaded songs box
      if (Hive.isBoxOpen('offline_songs')) {
        final box = Hive.box('offline_songs');
        for (final key in box.keys) {
          final raw = box.get(key);
          if (raw != null) {
            try {
              final Map<String, dynamic> json = raw is String ? jsonDecode(raw) : Map<String, dynamic>.from(raw as Map);
              final song = Song.fromJson(json);
              allLocalSongs[song.id] = song;
            } catch (_) {}
          }
        }
      }

      // 2. Check recently played box
      if (Hive.isBoxOpen('recentlyPlayed')) {
        final box = Hive.box<String>('recentlyPlayed');
        for (final key in box.keys) {
          final raw = box.get(key);
          if (raw != null) {
            try {
              final json = jsonDecode(raw) as Map<String, dynamic>;
              final song = Song.fromJson(json);
              allLocalSongs.putIfAbsent(song.id, () => song);
            } catch (_) {}
          }
        }
      }

      // 3. Check user playlists
      if (Hive.isBoxOpen('userPlaylists')) {
        final box = Hive.box<String>('userPlaylists');
        for (final key in box.keys) {
          final raw = box.get(key);
          if (raw != null) {
            try {
              final json = jsonDecode(raw) as Map<String, dynamic>;
              final songsList = json['songs'] as List? ?? [];
              for (final s in songsList) {
                if (s is Map) {
                  final song = Song.fromJson(Map<String, dynamic>.from(s));
                  allLocalSongs.putIfAbsent(song.id, () => song);
                }
              }
            } catch (_) {}
          }
        }
      }

      // Match and extract candidates
      final target = query.effectiveQuery.toLowerCase().trim();
      final candidates = <SearchCandidate>[];

      for (final song in allLocalSongs.values) {
        final songTitle = song.title.toLowerCase().trim();
        final songArtist = song.artist.toLowerCase().trim();

        // Exact, substring, or fuzzy similarity match
        final titleSim = StringSimilarity.levenshteinSimilarity(target, songTitle);
        final artistSim = StringSimilarity.levenshteinSimilarity(target, songArtist);
        final combined = '$songTitle $songArtist';
        final combinedSim = StringSimilarity.tokenOverlapScore(target, combined);

        if (songTitle.contains(target) ||
            songArtist.contains(target) ||
            target.contains(songTitle) ||
            titleSim > 0.4 ||
            artistSim > 0.4 ||
            combinedSim > 0.3) {
          candidates.add(SearchCandidate(
            canonicalId: song.id,
            youtubeId: song.youtubeUrl != null ? SearchCandidate.extractYtId(song.youtubeUrl!) : null,
            deezerId: song.deezerUrl,
            title: song.title,
            artist: song.artist,
            album: song.album ?? 'Local Collection',
            normalizedTitle: songTitle,
            normalizedArtist: songArtist,
            normalizedAlbum: song.album?.toLowerCase().trim(),
            duration: song.duration,
            language: song.language,
            versionType: _inferVersionType(song.title),
            sourceProvider: SearchProviderType.local,
            artworkUrl: song.albumArt,
            playableUrl: song.previewUrl,
            previewUrl: song.previewUrl,
            isDownloadable: true,
            matchedProviders: const [SearchProviderType.local],
          ));
        }
      }

      stopwatch.stop();
      health.recordSuccess(stopwatch.elapsed);
      return candidates;
    } catch (e) {
      stopwatch.stop();
      health.recordFailure(error: e.toString());
      debugPrint('[LocalSearchProvider] ⚠️ Error searching local collection: $e');
      return [];
    }
  }

  TrackVersionType _inferVersionType(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('remix')) return TrackVersionType.remix;
    if (lower.contains('live')) return TrackVersionType.live;
    if (lower.contains('acoustic')) return TrackVersionType.acoustic;
    if (lower.contains('cover')) return TrackVersionType.cover;
    if (lower.contains('slowed') || lower.contains('reverb')) return TrackVersionType.slowed;
    if (lower.contains('lofi') || lower.contains('lo-fi')) return TrackVersionType.lofi;
    if (lower.contains('karaoke')) return TrackVersionType.karaoke;
    if (lower.contains('lyrics')) return TrackVersionType.lyrics;
    return TrackVersionType.official;
  }
}
