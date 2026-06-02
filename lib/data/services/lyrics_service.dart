import 'package:dio/dio.dart';

class LyricsService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Fetches lyrics from LRCLIB (a free, open-source lyrics API requiring no auth).
  Future<String?> fetchLyrics(String title, String artist) async {
    try {
      // Clean up artist/title for better matching by stripping out extra tags
      String cleanTitle = title.replaceAll(RegExp(r'[\(\[\-\|].*'), '').trim();
      if (cleanTitle.isEmpty) cleanTitle = title;
      final cleanArtist = artist.split(',').first.trim();

      print('[Lyrics] 🎵 Fetching for: "$cleanTitle" by "$cleanArtist"');

      // ── API 1: LRCLIB (Exact Match) ──
      try {
        final response = await _dio.get(
          'https://lrclib.net/api/get',
          queryParameters: {
            'track_name': cleanTitle,
            'artist_name': cleanArtist,
          },
        );
        if (response.statusCode == 200 && response.data != null) {
          final plainLyrics = response.data['plainLyrics'] as String?;
          if (plainLyrics != null && plainLyrics.isNotEmpty) {
            if (_containsDevanagari(plainLyrics)) {
              print('[Lyrics] ℹ️ Found Devanagari on LRCLIB, checking for romanized...');
            } else {
              print('[Lyrics] ✅ Found on LRCLIB (Exact)');
              return plainLyrics;
            }
          }
        }
      } catch (_) {}

      // ── API 1.5: LRCLIB (Romanized Try) ──
      try {
        final romResponse = await _dio.get(
          'https://lrclib.net/api/search',
          queryParameters: {'q': '$cleanArtist $cleanTitle romanized'},
        );
        if (romResponse.statusCode == 200 && romResponse.data != null) {
          final List results = romResponse.data;
          if (results.isNotEmpty) {
            final plainLyrics = results.first['plainLyrics'] as String?;
            if (plainLyrics != null && plainLyrics.isNotEmpty && !_containsDevanagari(plainLyrics)) {
              print('[Lyrics] ✅ Found Romanized on LRCLIB');
              return plainLyrics;
            }
          }
        }
      } catch (_) {}

      // ── API 2: LRCLIB (Search Fallback) ──
      try {
        final searchResponse = await _dio.get(
          'https://lrclib.net/api/search',
          queryParameters: {'q': '$cleanArtist $cleanTitle'},
        );
        if (searchResponse.statusCode == 200 && searchResponse.data != null) {
          final List results = searchResponse.data;
          for (final res in results) {
            final resArtist = (res['artistName'] as String).toLowerCase();
            final reqArtist = cleanArtist.toLowerCase();
            
            // Validate that the artist actually matches to prevent wrong song lyrics
            if (resArtist.contains(reqArtist) || reqArtist.contains(resArtist)) {
              final plainLyrics = res['plainLyrics'] as String?;
              if (plainLyrics != null && plainLyrics.isNotEmpty) {
                if (_containsDevanagari(plainLyrics)) {
                   continue; // Look for a romanized version in the list if available
                }
                print('[Lyrics] ✅ Found valid match on LRCLIB (Search)');
                return plainLyrics;
              }
            }
          }
        }
      } catch (_) {}

      // ── API 3: Lyrics.ovh ──
      try {
        print('[Lyrics] 🔄 Falling back to Lyrics.ovh...');
        final ovhResponse = await _dio.get('https://api.lyrics.ovh/v1/$cleanArtist/$cleanTitle');
        if (ovhResponse.statusCode == 200 && ovhResponse.data != null) {
          final lyrics = ovhResponse.data['lyrics'] as String?;
          if (lyrics != null && lyrics.isNotEmpty) {
             print('[Lyrics] ✅ Found on Lyrics.ovh');
             // Lyrics.ovh sometimes prepends "Paroles de la chanson..."
             return lyrics.replaceAll(RegExp(r'Paroles de la chanson.*?\n'), '').trim();
          }
        }
      } catch (_) {}

      // ── API 4: Some Random API ──
      try {
        print('[Lyrics] 🔄 Falling back to Some Random API...');
        final srResponse = await _dio.get(
          'https://some-random-api.com/lyrics',
          queryParameters: {'title': '$cleanArtist $cleanTitle'},
        );
        if (srResponse.statusCode == 200 && srResponse.data != null) {
          final lyrics = srResponse.data['lyrics'] as String?;
          if (lyrics != null && lyrics.isNotEmpty) {
             print('[Lyrics] ✅ Found on Some Random API');
             return lyrics;
          }
        }
      } catch (_) {}

      print('[Lyrics] ❌ Exhausted all APIs. No lyrics found.');
      return null;
    } catch (e) {
      print('[Lyrics] ❌ Critical failure in lyrics pipeline: $e');
      return null;
    }
  }

  /// Detects if a string contains Hindi/Devanagari characters.
  bool _containsDevanagari(String text) {
    return RegExp(r'[\u0900-\u097F]').hasMatch(text);
  }
}

final lyricsService = LyricsService();
