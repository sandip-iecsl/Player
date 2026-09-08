import 'dart:async';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../domain/entities/song.dart';
import 'spotify_client_service.dart';
import 'jiosaavn_unofficial_api.dart';
import 'direct_jiosaavn_service.dart';
import 'lastfm_service.dart';
import 'search_enhancer.dart';
import 'hive_cache_manager.dart';
import 'local_taste_engine.dart';
import 'x007_music_service.dart';
import 'youtube_extractor_service.dart';

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
  final X007MusicService _x007 = X007MusicService();
  final YouTubeExtractorService _ytExtractor = YouTubeExtractorService();
  final Dio _lyricaDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  // ─── Autocomplete Cache ───────────────────────────────────────────────────
  Box? get _searchCacheBox {
    if (Hive.isBoxOpen('search_cache_box')) {
      return Hive.box('search_cache_box');
    }
    return null;
  }

  Future<Map<String, List<dynamic>>> getAutocomplete(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return {};

    // 0. URL Regex Interceptor: If user typed or pasted YouTube URL, extract single track
    if (YouTubeExtractorService.isYouTubeUrl(query)) {
      debugPrint('[Autocomplete] 🎯 Intercepted YouTube URL: "$query"');
      final ytSong = await _ytExtractor.extractTrack(query);
      if (ytSong != null) {
        return {
          'songs': [ytSong],
          'albums': [],
          'artists': [],
        };
      }
    }
    
    // 1. Local Cache Check
    final box = _searchCacheBox;
    if (box != null && box.containsKey(cleanQuery)) {
      debugPrint('[Autocomplete] Hive Cache HIT for: "$cleanQuery"');
      try {
        final cachedStr = box.get(cleanQuery) as String;
        final decodedWrap = jsonDecode(cachedStr) as Map<String, dynamic>;
        
        Map<String, dynamic> decodedData;
        if (decodedWrap.containsKey('data') && decodedWrap.containsKey('timestamp')) {
          decodedData = decodedWrap['data'] as Map<String, dynamic>;
        } else {
          // Backward compatibility: Old cache format
          decodedData = decodedWrap;
        }

        // Update timestamp for LRU access (putting it back to the box)
        final updatedWrap = {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'data': decodedData,
        };
        box.put(cleanQuery, jsonEncode(updatedWrap));

        return {
          'songs': (decodedData['songs'] as List?)?.map((s) => Song.fromJson(s)).toList() ?? [],
          'albums': decodedData['albums'] ?? [],
          'artists': decodedData['artists'] ?? [],
        };
      } catch (e) {
        debugPrint('[Autocomplete] Cache parse error: $e');
      }
    }
    
    debugPrint('[Autocomplete] Cache MISS for: "$cleanQuery", fetching...');
    
    // Use SearchEnhancer to expand short/typo queries to grab rich results
    final queries = SearchEnhancer.getExpandedQueries(query);
    
    final allSongs = <Song>[];
    final allAlbums = <dynamic>[];
    final allArtists = <dynamic>[];
    
    for (final q in queries) {
      // Parallel Handshake: Fetch from JioSaavn (both APIs) + LyricaV2 suggestion concurrently
      final futures = await Future.wait([
        _jioSaavnAPI.getAutocomplete(q).catchError((_) => <String, List<dynamic>>{}),
        _directJioSaavn.getAutocomplete(q).catchError((_) => <String, List<dynamic>>{}),
        _fetchLyricaSuggestions(q).catchError((_) => <Song>[]),
      ]);
      
      final results1 = futures[0] as Map<String, List<dynamic>>;
      final results2 = futures[1] as Map<String, List<dynamic>>;
      final lyricaSuggestions = futures[2] as List<Song>;

      if (results1['songs'] != null) allSongs.addAll(results1['songs'] as List<Song>);
      if (results2['songs'] != null) allSongs.addAll(results2['songs'] as List<Song>);

      // LyricaV2 suggestions enrich autocomplete with broader catalog matches
      allSongs.addAll(lyricaSuggestions);

      if (results1['albums'] != null) allAlbums.addAll(results1['albums']!);
      if (results2['albums'] != null) allAlbums.addAll(results2['albums']!);

      if (results1['artists'] != null) allArtists.addAll(results1['artists']!);
      if (results2['artists'] != null) allArtists.addAll(results2['artists']!);
    }
    
    // Deduplicate by title/id and filter unstreamable tracks
    final uniqueSongs = <String, Song>{};
    for (final s in allSongs) { 
      if (s.previewUrl == null || s.previewUrl!.isEmpty || s.previewUrl!.startsWith('unstreamable')) {
        continue;
      }
      uniqueSongs[s.id] = s; 
    }
    
    final uniqueAlbums = <String, dynamic>{};
    for (final a in allAlbums) { uniqueAlbums[a['id'] ?? a['title']] = a; }
    
    final uniqueArtists = <String, dynamic>{};
    for (final a in allArtists) { uniqueArtists[a['id'] ?? a['title']] = a; }
    
    final finalResults = {
      'songs': uniqueSongs.values.toList(),
      'albums': uniqueAlbums.values.toList(),
      'artists': uniqueArtists.values.toList(),
    };
    
    // Write to persistent cache
    if (box != null) {
      final toCache = {
        'songs': uniqueSongs.values.map((s) => s.toJson()).toList(),
        'albums': uniqueAlbums.values.toList(),
        'artists': uniqueArtists.values.toList(),
      };
      final wrapped = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': toCache,
      };
      await box.put(cleanQuery, jsonEncode(wrapped));
      
      // Enforce Least Recently Used eviction (capacity limit: 500)
      await HiveCacheManager.enforceCapacity(box);
    }

    return finalResults;
  }

  // ─── Search ──────────────────────────────────────────────────────────────

  Future<List<Song>> searchSongs(
    String rawQuery, {
    int limit = 20,
    int offset = 0,
    bool fullSongsOnly = false,
  }) async {
    if (rawQuery.trim().isEmpty) return [];

    // 0. URL Regex Interceptor: If user entered or pasted a YouTube URL, extract directly
    if (YouTubeExtractorService.isYouTubeUrl(rawQuery)) {
      debugPrint('[HybridSearch] 🎯 Intercepted YouTube URL: "$rawQuery"');
      final ytSong = await _ytExtractor.extractTrack(rawQuery);
      if (ytSong != null) {
        debugPrint('[HybridSearch] ✅ Returning extracted YouTube track: "${ytSong.title}"');
        return [ytSong];
      }
    }
    
    final query = SearchEnhancer.enhanceQuery(rawQuery);
    if (query != rawQuery.trim().toLowerCase()) {
      debugPrint('[HybridSearch] ✨ Enhanced query: "$rawQuery" -> "$query"');
    } else {
      debugPrint('[HybridSearch] 🔍 Searching for: "$query" (limit: $limit, offset: $offset)');
    }

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

    final fallbackResults = <Song>[];

    // 1. Unofficial JioSaavn API (fast, single request, returns streamable tracks)
    try {
      debugPrint('[HybridSearch] 🔄 Trying Unofficial JioSaavn API first...');
      final page = (offset ~/ limit) + 1;
      final raw = await _jioSaavnAPI.searchSongs(query, limit: limit, page: page);
      final results = _deduplicateSongs(raw, limit: limit, fullSongsOnly: fullSongsOnly);
      if (results.length >= 5) {
        debugPrint('[HybridSearch] ✅ ${results.length} results from Unofficial JioSaavn API');
        return _reRankByUserAffinity(results, query);
      } else if (results.isNotEmpty) {
        fallbackResults.addAll(results);
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Unofficial JioSaavn API failed: $e');
    }

    // 2. Direct JioSaavn search (fast, single request, returns streamable tracks)
    try {
      debugPrint('[HybridSearch] 🔄 Trying Direct JioSaavn...');
      final page = (offset ~/ limit) + 1;
      final raw = await _directJioSaavn.searchSongs(query, limit: limit, page: page);
      final results = _deduplicateSongs(raw, limit: limit, fullSongsOnly: fullSongsOnly);
      if (results.length >= 5) {
        debugPrint('[HybridSearch] ✅ ${results.length} results from Direct JioSaavn');
        return _reRankByUserAffinity(results, query);
      } else if (results.isNotEmpty) {
        final existingIds = fallbackResults.map((s) => s.id).toSet();
        fallbackResults.addAll(results.where((s) => !existingIds.contains(s.id)));
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Direct JioSaavn failed: $e');
    }

    // 2.5. x007 Multi-Engine Search (parallel across gaama + seevn + hunjama)
    try {
      debugPrint('[HybridSearch] 🔄 Trying x007 Multi-Engine search...');
      final x007Results = await _x007.searchSongs(query, limit: limit);
      if (x007Results.length >= 3) {
        // Try to enrich x007 results with JioSaavn metadata for better artist/album info
        final enriched = await _enrichX007Results(x007Results, limit: limit);
        if (enriched.isNotEmpty) {
          debugPrint('[HybridSearch] ✅ ${enriched.length} results from x007 (enriched)');
          return _reRankByUserAffinity(enriched, query);
        }
        debugPrint('[HybridSearch] ✅ ${x007Results.length} results from x007 (raw)');
        return _reRankByUserAffinity(x007Results, query);
      } else if (x007Results.isNotEmpty) {
        final existingIds = fallbackResults.map((s) => s.id).toSet();
        fallbackResults.addAll(x007Results.where((s) => !existingIds.contains(s.id)));
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ x007 search failed: $e');
    }

    // 3. Spotify search → get track names → find on JioSaavn (slower resolve fallback)
    try {
      debugPrint('[HybridSearch] 🔄 Trying Spotify metadata resolving fallback...');
      final spotifyTracks = await _spotify.searchTracks(query, limit: limit, offset: offset);
      if (spotifyTracks.isNotEmpty) {
        final songs = await _resolveTracksOnJioSaavn(spotifyTracks, limit: limit, fullSongsOnly: fullSongsOnly);
        if (songs.isNotEmpty) {
          debugPrint('[HybridSearch] ✅ ${songs.length} results via Spotify → JioSaavn');
          return songs;
        }
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Spotify search failed: $e');
    }

    // 4. Try Spotify recommendations based on the search query to suggest related songs!
    try {
      debugPrint('[HybridSearch] 🔄 Trying to find related recommendations for: "$query"...');
      final spotifyTracks = await _spotify.searchTracks(query, limit: 1);
      if (spotifyTracks.isNotEmpty) {
        final seedTrack = spotifyTracks.first;
        final recTracks = await _spotify.getRecommendations(
          seedTrackIds: [seedTrack.id],
          limit: limit,
        );
        if (recTracks.isNotEmpty) {
          final relatedSongs = await _resolveTracksOnJioSaavn(recTracks, limit: limit, fullSongsOnly: fullSongsOnly);
          if (relatedSongs.isNotEmpty) {
            debugPrint('[HybridSearch] ✅ Found ${relatedSongs.length} related recommendations for "$query"');
            return relatedSongs;
          }
        }
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Related recommendations fallback failed: $e');
    }

    // 4. Final fallback of partial results
    if (fallbackResults.isNotEmpty) {
      debugPrint('[HybridSearch] ✅ Returning ${fallbackResults.length} fallback results');
      return fallbackResults;
    }

    // FALLBACK A (No Exact Match): If a search returns 0 exact track matches,
    // route it to Spotify Recommendations using global genre seeds or fuzzy text matching.
    try {
      debugPrint('[HybridSearch] 🔄 Fallback A: Routing to Spotify Recommendations for: "$query"...');
      
      // 1. Try fuzzy matching against global trending items
      List<String> seedTrackIds = [];
      try {
        final trending = await getTrendingTracks(limit: 5);
        final queryClean = query.toLowerCase();
        for (final song in trending) {
          if (song.title.toLowerCase().contains(queryClean) || 
              song.artist.toLowerCase().contains(queryClean)) {
            final spotId = await _spotify.findTrackId(song.title, song.artist);
            if (spotId != null) {
              seedTrackIds.add(spotId);
              break;
            }
          }
        }
      } catch (_) {}

      // 2. Recommendations using seed tracks or global genre seeds
      final recTracks = await _spotify.getRecommendations(
        seedTrackIds: seedTrackIds,
        seedGenres: seedTrackIds.isEmpty ? ['bollywood', 'indian', 'desi', 'punjabi'] : [],
        limit: limit,
      );

      if (recTracks.isNotEmpty) {
        final resolvedSongs = await _resolveTracksOnJioSaavn(recTracks, limit: limit, fullSongsOnly: fullSongsOnly);
        if (resolvedSongs.isNotEmpty) {
          debugPrint('[HybridSearch] ✅ Fallback A loaded ${resolvedSongs.length} recommendation tracks.');
          return resolvedSongs;
        }
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Fallback A failed: $e');
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
            if (r.isNotEmpty) {
              final song = r.first;
              if (!fullSongsOnly || !_isFakeOrShort(song)) {
                final key = '${song.title.toLowerCase()}|${song.artist.toLowerCase()}';
                if (!seen.contains(key)) {
                  seen.add(key);
                  songs.add(song);
                }
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

    // 6. x007 Deep Fallback — try remaining engines (mtmusic, wunk)
    try {
      debugPrint('[HybridSearch] 🔄 x007 deep fallback (mtmusic + wunk)...');
      final deepResults = await _x007.searchSongs(
        query,
        limit: limit,
        engines: ['mtmusic', 'wunk'],
      );
      if (deepResults.isNotEmpty) {
        debugPrint('[HybridSearch] ✅ ${deepResults.length} results from x007 deep fallback');
        return _reRankByUserAffinity(deepResults, query);
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ x007 deep fallback failed: $e');
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

  /// Remove duplicate songs by normalized title, allow songs without previewUrl
  List<Song> _deduplicateSongs(
    List<Song> songs, {
    int limit = 20,
    bool fullSongsOnly = false,
  }) {
    final seenTitles = <String>{};
    final seenUrls   = <String>{};
    final result = <Song>[];
    for (final song in songs) {
      final titleKey = _normalizeTitle(song.title);
      final urlKey   = song.previewUrl ?? '';
      
      // Filter out garbage local-file tracks from Last.fm that pollute JioSaavn
      final lowerTitle = song.title.toLowerCase();
      if (lowerTitle.contains('pista ') || 
          lowerTitle.contains('spur ') || 
          lowerTitle.contains('ścieżka ') || 
          lowerTitle.contains('piste ')) {
        continue;
      }

      // Hide unstreamable tracks from search results entirely per user request
      if (urlKey.isEmpty || urlKey.startsWith('unstreamable')) {
        continue;
      }

      if (fullSongsOnly && _isFakeOrShort(song)) {
        continue;
      }

      if (seenTitles.contains(titleKey)) continue;
      if (urlKey.isNotEmpty && seenUrls.contains(urlKey)) continue;
      seenTitles.add(titleKey);
      if (urlKey.isNotEmpty) seenUrls.add(urlKey);
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
        final songs = await _resolveTracksOnJioSaavn(spotifyTracks, limit: limit, fullSongsOnly: true);
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
        if (r.isNotEmpty) {
          final s = r.first;
          if (_isFakeOrShort(s)) continue;
          final tk = _normalizeTitle(s.title);
          final uk = s.previewUrl ?? 'unstreamable_${s.id}';
          if (!seenTitles.contains(tk) && !seenUrls.contains(uk)) {
            seenTitles.add(tk);
            seenUrls.add(uk);
            songs.add(s);
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
    debugPrint('[HybridSearch] 📈 Getting trending tracks (Regional)');

    // Use a regional/bollywood query to prevent English songs on the dashboard
    return await searchSongs(
      'trending latest hindi bollywood hits',
      limit: limit,
      fullSongsOnly: true,
    );
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
          if (r.isNotEmpty) {
            final song = r.first;
            if (_isFakeOrShort(song)) continue;
            final tk = _normalizeTitle(song.title);
            final uk = song.previewUrl ?? 'unstreamable_${song.id}';
            if (!seenTitles.contains(tk) && !seenUrls.contains(uk)) {
              seenTitles.add(tk);
              seenUrls.add(uk);
              songs.add(song);
            }
          }
          if (songs.length >= limit) break;
        }
        if (songs.isNotEmpty) return songs;
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Genre tracks failed: $e');
    }

    return await searchSongs('$genre music', limit: limit, fullSongsOnly: true);
  }

  // ─── Artist top tracks ───────────────────────────────────────────────────

  Future<List<Song>> getArtistTopTracks(String artistName, {int limit = 20, int offset = 0}) async {
    final cleanArtist = artistName.trim().toLowerCase();
    if (cleanArtist == 'unknown artist' || cleanArtist == 'unknown') {
      debugPrint('[HybridSearch] 🛑 Ignoring artist search for Unknown Artist to prevent garbage results');
      return [];
    }

    debugPrint('[HybridSearch] 🎤 Getting top tracks for: "$artistName" (limit: $limit, offset: $offset)');

    // Try Spotify artist search first
    try {
      final artistId = await _spotify.searchArtistId(artistName);
      if (artistId != null) {
        final spotifyTracks = await _spotify.getArtistTopTracks(artistId, limit: limit + offset);
        if (spotifyTracks.isNotEmpty) {
          final songs = await _resolveTracksOnJioSaavn(spotifyTracks, limit: limit + offset, fullSongsOnly: true);
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
            if (r.isNotEmpty) {
              final song = r.first;
              if (_isFakeOrShort(song)) continue;
              final tk = _normalizeTitle(song.title);
              final uk = song.previewUrl ?? 'unstreamable_${song.id}';
              if (!seenTitles.contains(tk) && !seenUrls.contains(uk)) {
                seenTitles.add(tk);
                seenUrls.add(uk);
                songs.add(song);
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
      
      // Use the raw results directly since JioSaavn already ranks them by relevance to the artist query
      final filtered = results;
      
      if (filtered.isNotEmpty) {
        final deduped = _deduplicateSongs(filtered, limit: fetchLimit, fullSongsOnly: true);
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

    // Return empty so `searchSongs` can naturally fall back to regular search methods
    return [];
  }

  // ─── Helper: resolve Spotify tracks to JioSaavn stream URLs ─────────────

  Future<List<Song>> _resolveTracksOnJioSaavn(
    List<SpotifyTrack> tracks, {
    int limit = 20,
    bool fullSongsOnly = false,
  }) async {
    final songs = <Song>[];
    final seenKeys = <String>{};
    final seenUrls = <String>{};

    final dedupedTracks = <SpotifyTrack>[];
    for (final track in tracks) {
      final key = _normalizeTitle(track.title);
      if (!seenKeys.contains(key)) {
        seenKeys.add(key);
        dedupedTracks.add(track);
      }
    }
    seenKeys.clear();

    final resolveFutures = dedupedTracks.take(limit).map((track) async {
      final query = '${track.title} ${track.artist}';
      Song? resolved;

      try {
        final results = await _directJioSaavn.searchSongs(query, limit: 1);
        if (results.isNotEmpty) {
          resolved = results.first;
        }
      } catch (_) {}

      if (resolved == null) {
        try {
          final results = await _jioSaavnAPI.searchSongs(query, limit: 1);
          if (results.isNotEmpty) {
            resolved = results.first;
          }
        } catch (_) {}
      }

      // Allow songs without a previewUrl to support Fallback B
      final finalPreviewUrl = resolved?.previewUrl;
      return Song(
        id:         track.id,
        title:      track.title,
        artist:     track.artist,
        album:      track.album ?? resolved?.album,
        albumArt:   track.albumArt ?? resolved?.albumArt,
        duration:   track.durationMs > 0
                        ? Duration(milliseconds: track.durationMs)
                        : (resolved?.duration ?? Duration.zero),
        previewUrl: finalPreviewUrl,
      );
    }).toList();

    final resolvedResults = await Future.wait(resolveFutures);

    for (final song in resolvedResults) {
      if (fullSongsOnly && _isFakeOrShort(song)) continue;
      final titleKey = _normalizeTitle(song.title);
      final urlKey = song.previewUrl ?? '';

      if (seenKeys.contains(titleKey) || (urlKey.isNotEmpty && seenUrls.contains(urlKey))) continue;

      seenKeys.add(titleKey);
      if (urlKey.isNotEmpty) seenUrls.add(urlKey);
      songs.add(song);
    }

    return songs;
  }

  /// Checks whether a song is likely a short promo snippet or a fake remake.
  bool _isFakeOrShort(Song s) {
    final t = '${s.title} ${s.album ?? ''}'.toLowerCase();
    final isFakeTitle = t.contains('trending version') ||
        t.contains('trending remake') ||
        t.contains('(trending)') ||
        t.contains('speed up') ||
        t.contains('sped up') ||
        t.contains('slowed reverb') ||
        t.contains('lofi version') ||
        t.contains('(reverb)') ||
        t.contains('short version') ||
        t.contains('promo version') ||
        t.contains('teaser version') ||
        t.contains('short cover') ||
        t.contains('snippet');
    
    final isShort = s.duration.inSeconds > 0 && s.duration.inSeconds < 90;
    return isFakeTitle || isShort;
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

  /// Re-ranks search results by user affinity to surface songs by loved artists.
  /// Uses a blend of API position (relevance) and LocalTasteEngine affinity.
  /// Weight: 70% API relevance + 30% user affinity.
  List<Song> _reRankByUserAffinity(List<Song> results, String query) {
    if (results.isEmpty) return results;

    try {
      // Only re-rank if taste engine has been initialized and has history
      if (!Hive.isBoxOpen('listening_history')) return results;
      final artistHistory = Hive.box('listening_history').get('artists', defaultValue: {}) as Map;
      if (artistHistory.isEmpty) return results;

      final sorted = artistHistory.entries.toList()
        ..sort((a, b) => (b.value as int).compareTo(a.value as int));
      final topArtists = sorted.take(15).map((e) => e.key.toString().toLowerCase()).toSet();

      // Score each song: API-position score (0.7) + affinity boost (0.3)
      final scored = results.asMap().entries.map((entry) {
        final index = entry.key;
        final song = entry.value;
        final apiScore = 1.0 - (index / results.length); // 1.0 = first result
        
        double affinityBoost = 0.0;
        final songArtists = song.artist.toLowerCase().split(',').map((a) => a.trim());
        for (final artist in songArtists) {
          if (topArtists.any((top) => artist.contains(top) || top.contains(artist))) {
            affinityBoost += 0.4;
            break;
          }
        }

        final finalScore = (apiScore * 0.7) + (affinityBoost * 0.3);
        return MapEntry(song, finalScore);
      }).toList();

      scored.sort((a, b) => b.value.compareTo(a.value));
      debugPrint('[HybridSearch] ✨ Re-ranked ${results.length} results by user affinity');
      return scored.map((e) => e.key).toList();
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ Re-ranking failed, returning original order: $e');
      return results;
    }
  }

  /// Fetch song suggestions from LyricaV2 for autocomplete enrichment
  Future<List<Song>> _fetchLyricaSuggestions(String query) async {
    try {
      final response = await _lyricaDio.get(
        'https://wilooper-lyrica.hf.space/suggestion',
        queryParameters: {'q': query, 'limit': 5},
      );
      if (response.statusCode == 200 && response.data != null) {
        final List suggestions = response.data is List ? response.data : [];
        return suggestions.map((s) {
          return Song(
            id: 'lyrica_${s['id'] ?? s['title']?.hashCode ?? 0}',
            title: s['title']?.toString() ?? '',
            artist: s['artist']?.toString() ?? 'Unknown Artist',
            albumArt: s['thumbnail']?.toString(),
            album: s['album']?.toString(),
            duration: Duration.zero,
            previewUrl: null, // Needs resolution via JioSaavn
          );
        }).where((s) => s.title.isNotEmpty).toList();
      }
    } catch (e) {
      debugPrint('[HybridSearch] ⚠️ LyricaV2 suggestion failed: $e');
    }
    return [];
  }

  /// Enrich x007 results with JioSaavn metadata (artist, album, duration).
  /// x007 often returns good stream URLs but lacks rich metadata.
  Future<List<Song>> _enrichX007Results(List<Song> x007Songs, {int limit = 20}) async {
    final enriched = <Song>[];
    final enrichFutures = x007Songs.take(limit).map((song) async {
      try {
        // Try to find a matching JioSaavn track to get rich metadata
        final jioResults = await _directJioSaavn.searchSongs(song.title, limit: 1);
        if (jioResults.isNotEmpty) {
          final jio = jioResults.first;
          // Use x007's stream URL but JioSaavn's metadata
          return Song(
            id: song.id,
            title: jio.title,
            artist: jio.artist,
            albumArt: jio.albumArt ?? song.albumArt,
            album: jio.album,
            duration: jio.duration,
            previewUrl: song.previewUrl, // Keep x007 stream
          );
        }
      } catch (_) {}
      return song; // Return raw x007 song if enrichment fails
    });
    final results = await Future.wait(enrichFutures);
    enriched.addAll(results.whereType<Song>());
    return enriched;
  }

  void dispose() {
    _spotify.dispose();
    _jioSaavnAPI.dispose();
    _directJioSaavn.dispose();
    _lastFm.dispose();
    _x007.dispose();
    _lyricaDio.close();
  }
}
