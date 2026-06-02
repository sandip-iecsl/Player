import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/song.dart';
import 'spotify_client_service.dart';
import 'jiosaavn_unofficial_api.dart';
import 'direct_jiosaavn_service.dart';
import 'lastfm_service.dart';

/// Hybrid Search Service
/// 
/// Search:          Spotify metadata → JioSaavn stream URL
/// Recommendations: Spotify recommendations → JioSaavn stream URL
/// Trending:        Last.fm charts → JioSaavn stream URL
/// Fallback:        Direct JioSaavn search
class HybridSearchService {
  final SpotifyClientService _spotify = SpotifyClientService();
  final JioSaavnUnofficialAPI _jioSaavnAPI = JioSaavnUnofficialAPI();
  final DirectJioSaavnService _directJioSaavn = DirectJioSaavnService();
  final LastFmService _lastFm = LastFmService();

  // ─── Search ──────────────────────────────────────────────────────────────

  Future<List<Song>> searchSongs(String query, {int limit = 20, int offset = 0}) async {
    if (query.trim().isEmpty) return [];
    debugPrint('[HybridSearch] 🔍 Searching for: "$query" (limit: $limit, offset: $offset)');

    // Detect if query looks like an artist search (few words, no specific song indicators)
    final isLikelyArtistQuery = _isLikelyArtistQuery(query);
    
    if (isLikelyArtistQuery) {
      debugPrint('[HybridSearch] 🎤 Detected artist query, trying artist top tracks first');
      try {
        final artistSongs = await getArtistTopTracks(query, limit: limit, offset: offset);
        if (artistSongs.isNotEmpty) {
          debugPrint('[HybridSearch] ✅ ${artistSongs.length} results from artist search');
          return artistSongs;
        }
      } catch (e) {
        debugPrint('[HybridSearch] ⚠️ Artist search failed: $e, falling back to regular search');
      }
    }

    // 1. Spotify search → get track names → find on JioSaavn
    try {
      // Spotify supports offset, fetch more results
      final spotifyTracks = await _spotify.searchTracks(query, limit: limit, offset: offset);
      if (spotifyTracks.isNotEmpty) {
        final songs = await _resolveTracksOnJioSaavn(spotifyTracks, limit: limit);
        if (songs.isNotEmpty) {
          debugPrint('[HybridSearch] ✅ ${songs.length} results via Spotify → JioSaavn');
          return songs;
        }
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Spotify search failed: $e');
    }

    // 2. Direct JioSaavn search (fallback) — deduplicate by title
    // Note: JioSaavn doesn't support native pagination, so we fetch more and slice
    try {
      debugPrint('[HybridSearch] 🔄 Trying Direct JioSaavn...');
      final fetchLimit = limit + offset; // Fetch enough to cover offset
      final raw = await _directJioSaavn.searchSongs(query, limit: fetchLimit * 2);
      final results = _deduplicateSongs(raw, limit: fetchLimit);
      
      // Apply offset manually
      if (results.length > offset) {
        final paginated = results.skip(offset).take(limit).toList();
        if (paginated.isNotEmpty) {
          debugPrint('[HybridSearch] ✅ ${paginated.length} results from Direct JioSaavn');
          return paginated;
        }
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Direct JioSaavn failed: $e');
    }

    // 3. Last.fm discovery → JioSaavn
    // Last.fm has limited results, only use for first page
    if (offset == 0) {
      try {
        debugPrint('[HybridSearch] 🔄 Trying Last.fm discovery...');
        final lastFmTracks = await _lastFm.searchTracks(query, limit: limit);
        if (lastFmTracks.isNotEmpty) {
          final songs = <Song>[];
          final seen = <String>{};
          for (final t in lastFmTracks.take(limit)) {
            final q = '${t['name']} ${t['artist']}';
            final r = await _directJioSaavn.searchSongs(q, limit: 1);
            if (r.isNotEmpty && r.first.previewUrl != null) {
              final key = '${r.first.title.toLowerCase()}|${r.first.artist.toLowerCase()}';
              if (!seen.contains(key)) {
                seen.add(key);
                songs.add(r.first);
              }
            }
            if (songs.length >= limit) break;
          }
          if (songs.isNotEmpty) {
            debugPrint('[HybridSearch] ✅ ${songs.length} results via Last.fm → JioSaavn');
            return songs;
          }
        }
      } catch (e) {
        debugPrint('[HybridSearch] ⚠️ Last.fm discovery failed: $e');
      }
    }

    debugPrint('[HybridSearch] ❌ No results found');
    return [];
  }

  /// Detect if a search query is likely looking for an artist rather than a song
  bool _isLikelyArtistQuery(String query) {
    final normalized = query.toLowerCase().trim();
    
    // Common artist name patterns - typically 1-3 words without song-specific terms
    final wordCount = normalized.split(RegExp(r'\s+')).length;
    
    // Song-specific indicators
    final songIndicators = [
      'song', 'feat', 'ft', 'remix', 'cover', 'lyrics', 'audio', 'video',
      'official', 'album', 'track', 'live', 'version', 'unplugged', 'acoustic',
      'new', 'latest', 'best', 'top', 'hits', 'releases', 'release', 'bollywood',
      'hindi', 'english', 'trending', 'popular', '2024', '2025', '2026', '2023'
    ];
    
    final hasSongIndicator = songIndicators.any((indicator) => 
      normalized.contains(indicator));
    
    // If 1-3 words and no song indicators, likely an artist
    // Also consider common artist name patterns
    if (wordCount >= 1 && wordCount <= 3 && !hasSongIndicator) {
      // Additional check: if it's just a number or very generic, probably not an artist
      if (RegExp(r'^\d+$').hasMatch(normalized)) {
        return false;
      }
      return true;
    }
    
    return false;
  }

  /// Remove duplicate songs by normalized title, keep only songs with stream URLs
  List<Song> _deduplicateSongs(List<Song> songs, {int limit = 20}) {
    final seenTitles = <String>{};
    final seenUrls   = <String>{};
    final result = <Song>[];
    for (final song in songs) {
      if (song.previewUrl == null || song.previewUrl!.isEmpty) continue;
      final titleKey = _normalizeTitle(song.title);
      final urlKey   = song.previewUrl!;
      if (seenTitles.contains(titleKey)) continue;
      if (seenUrls.contains(urlKey)) continue;
      seenTitles.add(titleKey);
      seenUrls.add(urlKey);
      result.add(song);
      if (result.length >= limit) break;
    }
    return result;
  }

  // ─── Recommendations ─────────────────────────────────────────────────────

  Future<List<Song>> getRecommendations(Song song, {int limit = 20}) async {
    debugPrint('[HybridSearch] 🎵 Getting recommendations for: "${song.title}"');

    try {
      // Find Spotify track ID for the current song
      final trackId = await _spotify.findTrackId(song.title, song.artist);
      final artistId = trackId != null ? null : await _spotify.searchArtistId(song.artist);

      final spotifyTracks = await _spotify.getRecommendations(
        seedTrackIds:  trackId  != null ? [trackId]  : [],
        seedArtistIds: artistId != null ? [artistId] : [],
        limit: limit,
      );

      if (spotifyTracks.isNotEmpty) {
        final songs = await _resolveTracksOnJioSaavn(spotifyTracks, limit: limit);
        if (songs.isNotEmpty) {
          debugPrint('[HybridSearch] ✅ ${songs.length} recommendations via Spotify');
          return songs;
        }
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Spotify recommendations failed: $e');
    }

    // Fallback: Last.fm similar tracks
    try {
      final similar = await _lastFm.getSimilarTracks(song.title, song.artist, limit: limit);
      final songs = <Song>[];
      final seenTitles = <String>{};
      final seenUrls   = <String>{};
      for (final t in similar.take(limit * 2)) {
        final r = await _directJioSaavn.searchSongs('${t['name']} ${t['artist']}', limit: 1);
        if (r.isNotEmpty && r.first.previewUrl != null) {
          final tk = _normalizeTitle(r.first.title);
          final uk = r.first.previewUrl!;
          if (!seenTitles.contains(tk) && !seenUrls.contains(uk)) {
            seenTitles.add(tk);
            seenUrls.add(uk);
            songs.add(r.first);
          }
        }
        if (songs.length >= limit) break;
      }
      if (songs.isNotEmpty) return songs;
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Last.fm similar tracks failed: $e');
    }

    return [];
  }

  // ─── Trending ────────────────────────────────────────────────────────────

  Future<List<Song>> getTrendingTracks({int limit = 20}) async {
    debugPrint('[HybridSearch] 📈 Getting trending tracks');

    // Last.fm top charts → JioSaavn
    try {
      final topTracks = await _lastFm.getTopTracks(limit: limit);
      if (topTracks.isNotEmpty) {
        final songs = <Song>[];
        final seenTitles = <String>{};
        final seenUrls   = <String>{};
        for (final t in topTracks.take(limit * 2)) {
          final r = await _directJioSaavn.searchSongs('${t['name']} ${t['artist']}', limit: 1);
          if (r.isNotEmpty && r.first.previewUrl != null) {
            final tk = _normalizeTitle(r.first.title);
            final uk = r.first.previewUrl!;
            if (!seenTitles.contains(tk) && !seenUrls.contains(uk)) {
              seenTitles.add(tk);
              seenUrls.add(uk);
              songs.add(r.first);
            }
          }
          if (songs.length >= limit) break;
        }
        if (songs.isNotEmpty) {
          debugPrint('[HybridSearch] ✅ ${songs.length} trending tracks');
          return songs;
        }
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Trending failed: $e');
    }

    return await searchSongs('trending hits 2024', limit: limit);
  }

  // ─── Genre ───────────────────────────────────────────────────────────────

  Future<List<Song>> getTracksByGenre(String genre, {int limit = 20}) async {
    debugPrint('[HybridSearch] 🏷️ Getting tracks for genre: "$genre"');

    try {
      final tagTracks = await _lastFm.getTopTracksByTag(genre, limit: limit);
      if (tagTracks.isNotEmpty) {
        final songs = <Song>[];
        final seenTitles = <String>{};
        final seenUrls   = <String>{};
        for (final t in tagTracks.take(limit * 2)) {
          final r = await _directJioSaavn.searchSongs('${t['name']} ${t['artist']}', limit: 1);
          if (r.isNotEmpty && r.first.previewUrl != null) {
            final tk = _normalizeTitle(r.first.title);
            final uk = r.first.previewUrl!;
            if (!seenTitles.contains(tk) && !seenUrls.contains(uk)) {
              seenTitles.add(tk);
              seenUrls.add(uk);
              songs.add(r.first);
            }
          }
          if (songs.length >= limit) break;
        }
        if (songs.isNotEmpty) return songs;
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Genre tracks failed: $e');
    }

    return await searchSongs('$genre music', limit: limit);
  }

  // ─── Artist top tracks ───────────────────────────────────────────────────

  Future<List<Song>> getArtistTopTracks(String artistName, {int limit = 20, int offset = 0}) async {
    debugPrint('[HybridSearch] 🎤 Getting top tracks for: "$artistName" (limit: $limit, offset: $offset)');

    // Try Spotify artist search first
    try {
      final artistId = await _spotify.searchArtistId(artistName);
      if (artistId != null) {
        final spotifyTracks = await _spotify.getArtistTopTracks(artistId, limit: limit + offset);
        if (spotifyTracks.isNotEmpty) {
          final songs = await _resolveTracksOnJioSaavn(spotifyTracks, limit: limit + offset);
          // Apply offset manually for artist tracks
          if (songs.length > offset) {
            final paginated = songs.skip(offset).take(limit).toList();
            if (paginated.isNotEmpty) {
              debugPrint('[HybridSearch] ✅ ${paginated.length} artist top tracks from Spotify');
              return paginated;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Spotify artist top tracks failed: $e');
    }

    // Fallback: Try Last.fm artist top tracks
    // Last.fm has limited results, mainly for first page
    if (offset < 50) {
      try {
        debugPrint('[HybridSearch] 🔄 Trying Last.fm for artist top tracks...');
        final lastFmTracks = await _lastFm.getArtistTopTracks(artistName, limit: limit + offset);
        if (lastFmTracks.isNotEmpty) {
          final songs = <Song>[];
          final seenTitles = <String>{};
          final seenUrls   = <String>{};
          for (final t in lastFmTracks.skip(offset).take(limit * 2)) {
            final r = await _directJioSaavn.searchSongs('${t['name']} ${t['artist']}', limit: 1);
            if (r.isNotEmpty && r.first.previewUrl != null) {
              final tk = _normalizeTitle(r.first.title);
              final uk = r.first.previewUrl!;
              if (!seenTitles.contains(tk) && !seenUrls.contains(uk)) {
                seenTitles.add(tk);
                seenUrls.add(uk);
                songs.add(r.first);
              }
            }
            if (songs.length >= limit) break;
          }
          if (songs.isNotEmpty) {
            debugPrint('[HybridSearch] ✅ ${songs.length} artist top tracks from Last.fm');
            return songs;
          }
        }
      } catch (e) {
        debugPrint('[HybridSearch] ⚠️ Last.fm artist top tracks failed: $e');
      }
    }

    // Final fallback: Direct search on JioSaavn with artist filter
    try {
      debugPrint('[HybridSearch] 🔄 Trying direct JioSaavn with artist filter...');
      final fetchLimit = (limit + offset) * 2;
      final results = await _directJioSaavn.searchSongs(artistName, limit: fetchLimit);
      
      // Filter results to only include songs where the artist name appears in the artist field
      final artistLower = artistName.toLowerCase();
      final filtered = results.where((song) => 
        song.artist.toLowerCase().contains(artistLower)
      ).toList();
      
      if (filtered.isNotEmpty) {
        final deduped = _deduplicateSongs(filtered, limit: fetchLimit);
        // Apply offset
        if (deduped.length > offset) {
          final paginated = deduped.skip(offset).take(limit).toList();
          debugPrint('[HybridSearch] ✅ ${paginated.length} filtered artist results from JioSaavn');
          return paginated;
        }
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Direct JioSaavn artist filter failed: $e');
    }

    // Last resort: regular search with pagination
    return await searchSongs(artistName, limit: limit, offset: offset);
  }

  // ─── Helper: resolve Spotify tracks to JioSaavn stream URLs ─────────────

  Future<List<Song>> _resolveTracksOnJioSaavn(
    List<SpotifyTrack> tracks, {
    int limit = 20,
  }) async {
    final songs = <Song>[];
    final seenKeys   = <String>{}; // deduplicate by normalized title
    final seenUrls   = <String>{}; // deduplicate by stream URL (catches same song from diff albums)

    // Deduplicate Spotify tracks BEFORE resolving — same title wins first occurrence
    final dedupedTracks = <SpotifyTrack>[];
    for (final track in tracks) {
      final key = _normalizeTitle(track.title);
      if (!seenKeys.contains(key)) {
        seenKeys.add(key);
        dedupedTracks.add(track);
      }
    }
    seenKeys.clear(); // reset for second pass

    for (final track in dedupedTracks) {
      if (songs.length >= limit) break;

      final titleKey = _normalizeTitle(track.title);
      if (seenKeys.contains(titleKey)) continue;

      final query = '${track.title} ${track.artist}';
      Song? resolved;

      // Try direct JioSaavn first
      try {
        final results = await _directJioSaavn.searchSongs(query, limit: 1);
        if (results.isNotEmpty && results.first.previewUrl != null) {
          resolved = results.first;
        }
      } catch (_) {}

      // Fallback: unofficial API
      if (resolved == null) {
        try {
          final results = await _jioSaavnAPI.searchSongs(query, limit: 1);
          if (results.isNotEmpty && results.first.previewUrl != null) {
            resolved = results.first;
          }
        } catch (_) {}
      }

      if (resolved == null) continue;

      // Skip if we already have this stream URL (same song, different Spotify entry)
      final urlKey = resolved.previewUrl!;
      if (seenUrls.contains(urlKey)) continue;

      seenKeys.add(titleKey);
      seenUrls.add(urlKey);

      songs.add(Song(
        id:         track.id,
        title:      track.title,
        artist:     track.artist,
        album:      track.album ?? resolved.album,
        albumArt:   track.albumArt ?? resolved.albumArt,
        duration:   track.durationMs > 0
                        ? Duration(milliseconds: track.durationMs)
                        : resolved.duration,
        previewUrl: resolved.previewUrl,
      ));
    }

    return songs;
  }

  /// Normalize a title for deduplication:
  /// - lowercase
  /// - remove content in parentheses/brackets (e.g. "(From "Movie")", "[Remix]")
  /// - remove extra whitespace
  String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)'), '') // remove (...)
        .replaceAll(RegExp(r'\[.*?\]'), '') // remove [...]
        .replaceAll(RegExp(r'feat\..*', caseSensitive: false), '') // remove feat.
        .replaceAll(RegExp(r'ft\..*',   caseSensitive: false), '') // remove ft.
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '') // keep only alphanumeric
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void dispose() {
    _spotify.dispose();
    _jioSaavnAPI.dispose();
    _directJioSaavn.dispose();
    _lastFm.dispose();
  }
}
