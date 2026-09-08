import 'package:dio/dio.dart';
import '../../domain/entities/lyrics_data.dart';

class LyricsService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent': 'AuraPlayer/1.0 (https://github.com/aura-player)',
    },
  ));

  // Simple in-memory cache to avoid redundant fetches
  final Map<String, LyricsData?> _cache = {};

  String _decodeHtml(String input) {
    return input
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
  }

  Future<LyricsData?> fetchLyrics(String title, String artist, {Duration? duration}) async {
    final decodedTitle = _decodeHtml(title);
    final decodedArtist = _decodeHtml(artist);

    final cacheKey = '${decodedTitle.toLowerCase().trim()}|${decodedArtist.toLowerCase().trim()}';
    if (_cache.containsKey(cacheKey)) {
      print('[Lyrics] 📦 Cache hit for "$decodedTitle"');
      return _cache[cacheKey];
    }

    try {
      // Clean title: remove anything in brackets/parentheses, after dash/pipe
      String cleanTitle = decodedTitle
          .replaceAll(RegExp(r'[\(\[\-\|].*'), '')
          .replaceAll(RegExp(r'\s*\(.*?\)\s*'), '')
          .replaceAll(RegExp(r'\s*\[.*?\]\s*'), '')
          .trim();
      if (cleanTitle.isEmpty) cleanTitle = decodedTitle.trim();

      // Clean artist: take first name before comma/ampersand/feat
      final cleanArtist = decodedArtist
          .split(RegExp(r'[,&]'))
          .first
          .replaceAll(RegExp(r'\s*feat\.?\s*.*', caseSensitive: false), '')
          .trim();

      print('[Lyrics] 🎵 Fetching for: "$cleanTitle" by "$cleanArtist" (duration: ${duration?.inSeconds}s)');

      LyricsData? result;

      // ── Source 1: LRCLIB (Best - Free, Open, Synced LRC + Plain) ──
      result = await _tryLrclib(cleanTitle, cleanArtist, duration: duration);
      if (result != null && !result.isEmpty) {
        _cache[cacheKey] = result;
        return result;
      }

      // Retry without duration as fallback for strict duration mismatch
      if (duration != null) {
        result = await _tryLrclib(cleanTitle, cleanArtist, duration: null);
        if (result != null && !result.isEmpty) {
          _cache[cacheKey] = result;
          return result;
        }
      }

      // ── Source 2: LRCLIB Search (broader query match) ──
      result = await _tryLrclibSearch(cleanTitle, cleanArtist);
      if (result != null && !result.isEmpty) {
        _cache[cacheKey] = result;
        return result;
      }

      // ── Source 3: Lyrics.ovh (Simple plain-text lyrics) ──
      result = await _tryLyricsOvh(cleanTitle, cleanArtist);
      if (result != null && !result.isEmpty) {
        _cache[cacheKey] = result;
        return result;
      }

      // ── Source 4: LyricaV2 HuggingFace (original primary) ──
      result = await _tryLyricaV2(cleanTitle, cleanArtist);
      if (result != null && !result.isEmpty) {
        _cache[cacheKey] = result;
        return result;
      }

      // ── Source 5: x007 Gaama API (original fallback) ──
      result = await _tryX007Gaama(cleanTitle, cleanArtist);
      if (result != null && !result.isEmpty) {
        _cache[cacheKey] = result;
        return result;
      }

      // ── Source 6: Retry LRCLIB with original (uncleaned) title ──
      if (cleanTitle != decodedTitle.trim()) {
        result = await _tryLrclibSearch(decodedTitle.trim(), decodedArtist.trim());
        if (result != null && !result.isEmpty) {
          _cache[cacheKey] = result;
          return result;
        }
      }

      print('[Lyrics] ❌ Exhausted all sources. No lyrics found.');
      _cache[cacheKey] = null;
      return null;
    } catch (e) {
      print('[Lyrics] ❌ Critical failure in lyrics pipeline: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────
  // Source 1: LRCLIB - Direct GET by track_name + artist_name
  // https://lrclib.net/api/get?track_name=...&artist_name=...
  // ─────────────────────────────────────────────────────────
  Future<LyricsData?> _tryLrclib(String title, String artist, {Duration? duration}) async {
    try {
      print('[Lyrics] 🔍 Trying LRCLIB (direct)...');
      final Map<String, dynamic> params = {
        'track_name': title,
        'artist_name': artist,
      };
      if (duration != null && duration.inSeconds > 0) {
        params['duration'] = duration.inSeconds.toString();
      }

      final response = await _dio.get(
        'https://lrclib.net/api/get',
        queryParameters: params,
      );

      if (response.statusCode == 200 && response.data != null) {
        return _parseLrclibResponse(response.data);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        print('[Lyrics] ⚠️ LRCLIB: Not found (404)');
      } else {
        print('[Lyrics] ⚠️ LRCLIB direct failed: ${e.message}');
      }
    } catch (e) {
      print('[Lyrics] ⚠️ LRCLIB direct failed: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────
  // Source 2: LRCLIB - Search endpoint (broader matching)
  // https://lrclib.net/api/search?q=...
  // ─────────────────────────────────────────────────────────
  Future<LyricsData?> _tryLrclibSearch(String title, String artist) async {
    try {
      print('[Lyrics] 🔍 Trying LRCLIB (search)...');
      final response = await _dio.get(
        'https://lrclib.net/api/search',
        queryParameters: {
          'q': '$artist $title',
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final List results = response.data as List;
        if (results.isNotEmpty) {
          // Try to find the best match - prefer one with synced lyrics
          Map<String, dynamic>? bestMatch;
          for (final item in results) {
            final syncedLyrics = item['syncedLyrics'] as String?;
            if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
              bestMatch = item as Map<String, dynamic>;
              break;
            }
          }
          // If no synced match, take the first with plain lyrics
          bestMatch ??= results.first as Map<String, dynamic>;
          return _parseLrclibResponse(bestMatch);
        }
      }
    } on DioException catch (e) {
      print('[Lyrics] ⚠️ LRCLIB search failed: ${e.message}');
    } catch (e) {
      print('[Lyrics] ⚠️ LRCLIB search failed: $e');
    }
    return null;
  }

  /// Parses a LRCLIB response object into LyricsData
  LyricsData? _parseLrclibResponse(Map<String, dynamic> data) {
    // Prefer synced lyrics (LRC format)
    final String? syncedLyrics = data['syncedLyrics'] as String?;
    if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
      final parsed = _parseLrc(syncedLyrics);
      if (parsed.isNotEmpty) {
        print('[Lyrics] ✅ Found synced lyrics on LRCLIB');
        return LyricsData(lines: parsed);
      }
    }

    // Fall back to plain lyrics
    final String? plainLyrics = data['plainLyrics'] as String?;
    if (plainLyrics != null && plainLyrics.isNotEmpty) {
      print('[Lyrics] ✅ Found plain lyrics on LRCLIB');
      return LyricsData(plainLyrics: plainLyrics);
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────
  // Source 3: Lyrics.ovh - Simple REST API for plain lyrics
  // https://api.lyrics.ovh/v1/{artist}/{title}
  // ─────────────────────────────────────────────────────────
  Future<LyricsData?> _tryLyricsOvh(String title, String artist) async {
    try {
      print('[Lyrics] 🔍 Trying Lyrics.ovh...');
      final encodedArtist = Uri.encodeComponent(artist);
      final encodedTitle = Uri.encodeComponent(title);
      final response = await _dio.get(
        'https://api.lyrics.ovh/v1/$encodedArtist/$encodedTitle',
      );

      if (response.statusCode == 200 && response.data != null) {
        final String? lyrics = response.data['lyrics'] as String?;
        if (lyrics != null && lyrics.trim().isNotEmpty) {
          print('[Lyrics] ✅ Found on Lyrics.ovh');
          return LyricsData(plainLyrics: lyrics.trim());
        }
      }
    } on DioException catch (e) {
      print('[Lyrics] ⚠️ Lyrics.ovh failed: ${e.message}');
    } catch (e) {
      print('[Lyrics] ⚠️ Lyrics.ovh failed: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────
  // Source 4: LyricaV2 (HuggingFace - original primary)
  // ─────────────────────────────────────────────────────────
  Future<LyricsData?> _tryLyricaV2(String title, String artist) async {
    try {
      print('[Lyrics] 🔍 Trying LyricaV2 (HuggingFace)...');
      final response = await _dio.get(
        'https://wilooper-lyrica.hf.space/lyrics/',
        queryParameters: {
          'artist': artist,
          'song': title,
          'timestamps': 'true',
          'fast': 'true',
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final String? rawLyrics = response.data['lyrics'] as String?;
        if (rawLyrics != null && rawLyrics.isNotEmpty) {
          print('[Lyrics] ✅ Found on LyricaV2');
          final parsed = _parseLrc(rawLyrics);
          if (parsed.isNotEmpty) {
            return LyricsData(lines: parsed);
          } else {
            return LyricsData(plainLyrics: rawLyrics);
          }
        }
      }
    } catch (e) {
      print('[Lyrics] ⚠️ LyricaV2 failed: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────
  // Source 5: x007 Gaama API (original fallback)
  // ─────────────────────────────────────────────────────────
  Future<LyricsData?> _tryX007Gaama(String title, String artist) async {
    try {
      print('[Lyrics] 🔍 Trying x007 API (gaama)...');
      final searchResponse = await _dio.get(
        'https://musicapi.x007.workers.dev/search',
        queryParameters: {
          'q': '$artist $title',
          'searchEngine': 'gaama',
        },
      );

      if (searchResponse.statusCode == 200 && searchResponse.data != null) {
        final res = searchResponse.data['response'] as List?;
        if (res != null && res.isNotEmpty) {
          final firstSongId = res.first['id'];

          final lyricsResponse = await _dio.get(
            'https://musicapi.x007.workers.dev/lyrics',
            queryParameters: {'id': firstSongId},
          );

          if (lyricsResponse.statusCode == 200 && lyricsResponse.data != null) {
            final rawLyricsHtml = lyricsResponse.data['response'] as String?;
            if (rawLyricsHtml != null && rawLyricsHtml.isNotEmpty) {
              // Strip HTML tags
              String plain = rawLyricsHtml
                  .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
                  .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
                  .replaceAll(RegExp(r'<[^>]+>'), '')
                  .trim();

              // Collapse multiple newlines
              plain = plain.replaceAll(RegExp(r'\n{3,}'), '\n\n');

              if (plain.isNotEmpty) {
                print('[Lyrics] ✅ Found on x007 API');
                return LyricsData(plainLyrics: plain);
              }
            }
          }
        }
      }
    } catch (e) {
      print('[Lyrics] ⚠️ x007 API failed: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────
  // LRC Parser - Handles [mm:ss.xx] format
  // ─────────────────────────────────────────────────────────
  List<LyricsLine> _parseLrc(String rawLrc) {
    final List<LyricsLine> lines = [];
    final regex = RegExp(r'\[(\d+):([\d\.]+)\](.*)');
    final linesSplit = rawLrc.split('\n');

    for (final line in linesSplit) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = double.tryParse(match.group(2) ?? '0') ?? 0.0;
        final text = match.group(3)?.trim() ?? '';

        final timestamp = Duration(
          minutes: minutes,
          milliseconds: (seconds * 1000).toInt(),
        );

        if (text.isNotEmpty) {
          lines.add(LyricsLine(timestamp: timestamp, text: text));
        }
      }
    }

    // Sort by timestamp to ensure correct order
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }

  /// Clear the in-memory lyrics cache
  void clearCache() {
    _cache.clear();
    print('[Lyrics] 🗑️ Cache cleared');
  }
}

final lyricsService = LyricsService();
