import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import '../../domain/entities/song.dart';

/// Direct JioSaavn Service
/// Uses JioSaavn's internal API (same one their website uses)
class DirectJioSaavnService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Origin': 'https://www.jiosaavn.com',
      'Referer': 'https://www.jiosaavn.com/',
    },
  ));

  static const String _baseUrl = 'https://www.jiosaavn.com/api.php';

  /// Search for songs using JioSaavn's search.getResults endpoint
  Future<List<Song>> searchSongs(String query, {int limit = 20, int page = 1}) async {
    if (query.trim().isEmpty) return [];

    debugPrint('[DirectJioSaavn] 🔍 Searching for: "$query" (limit: $limit, page: $page)');

    try {
      final response = await _dio.get(
        _baseUrl,
        queryParameters: {
          '__call': 'search.getResults',
          '_format': 'json',
          '_marker': '0',
          'api_version': '4',
          'ctx': 'web6dot0',
          'q': query,
          'n': limit.toString(),
          'p': page.toString(),
        },
        options: Options(
          responseType: ResponseType.plain, // Get raw string, parse manually
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      debugPrint('[DirectJioSaavn] 📡 Status: ${response.statusCode}');

      if (response.statusCode == 200 && response.data != null) {
        final rawString = response.data.toString();

        // Parse JSON
        Map<String, dynamic> data;
        try {
          data = jsonDecode(rawString) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('[DirectJioSaavn] ❌ JSON parse failed: $e');
          return [];
        }

        final songs = <Song>[];

        // search.getResults returns: { total, start, results: [...] }
        List? results;
        if (data['results'] != null && data['results'] is List) {
          results = data['results'] as List;
        } else if (data['data'] != null && data['data'] is List) {
          results = data['data'] as List;
        }

        if (results == null || results.isEmpty) {
          debugPrint('[DirectJioSaavn] ⚠️ No results in response. Keys: ${data.keys.toList()}');
          return [];
        }

        debugPrint('[DirectJioSaavn] 📋 Found ${results.length} results');

        for (final item in results.take(limit)) {
          try {
            if (item is Map<String, dynamic>) {
              final song = _parseSong(item);
              if (song.previewUrl != null && song.previewUrl!.isNotEmpty) {
                songs.add(song);
              }
            }
          } catch (e) {
            debugPrint('[DirectJioSaavn] ⚠️ Parse error: $e');
          }
        }

        debugPrint('[DirectJioSaavn] ✅ Returning ${songs.length} songs with URLs');
        return songs;
      }
    } catch (e, st) {
      debugPrint('[DirectJioSaavn] ❌ Search failed: $e');
      debugPrint('[DirectJioSaavn] $st');
    }

    return [];
  }

  /// Get search autocomplete suggestions using direct JioSaavn API
  Future<Map<String, List<dynamic>>> getAutocomplete(String query) async {
    if (query.trim().isEmpty) return {};

    try {
      final response = await _dio.get(
        _baseUrl,
        queryParameters: {
          '__call': 'autocomplete.get',
          '_format': 'json',
          '_marker': '0',
          'api_version': '4',
          'ctx': 'web6dot0',
          'query': query,
        },
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final rawString = response.data.toString();
        Map<String, dynamic> data;
        try {
          data = jsonDecode(rawString) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('[DirectJioSaavn] ❌ JSON parse failed for autocomplete: $e');
          return {};
        }

        final songs = <Song>[];
        final albums = <dynamic>[];
        final artists = <dynamic>[];

        if (data['songs'] != null && data['songs']['data'] is List) {
          final songsData = data['songs']['data'] as List;
          for (final item in songsData) {
            try {
              if (item is Map<String, dynamic>) {
                songs.add(_parseSong(item));
              }
            } catch (_) {}
          }
        }

        if (data['albums'] != null && data['albums']['data'] is List) {
          albums.addAll(data['albums']['data'] as List);
        }

        if (data['artists'] != null && data['artists']['data'] is List) {
          artists.addAll(data['artists']['data'] as List);
        }

        return {
          'songs': songs,
          'albums': albums,
          'artists': artists,
        };
      }
    } catch (e) {
      debugPrint('[DirectJioSaavn] ❌ Autocomplete failed: $e');
    }

    return {};
  }

  Song _parseSong(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final title = _clean(json['title']?.toString() ?? json['song']?.toString() ?? 'Unknown');

    // Artist
    String artist = 'Unknown Artist';
    final moreInfo = json['more_info'];
    if (moreInfo is Map) {
      final mi = moreInfo as Map<String, dynamic>;
      // Try artistMap.primary_artists
      final artistMap = mi['artistMap'];
      if (artistMap is Map) {
        final primary = (artistMap as Map<String, dynamic>)['primary_artists'];
        if (primary is List && primary.isNotEmpty) {
          artist = primary
              .where((a) => a is Map && a['name'] != null)
              .map((a) => (a as Map)['name'].toString())
              .join(', ');
        }
      }
      // Fallback to singers
      if (artist == 'Unknown Artist' && mi['singers'] != null) {
        artist = mi['singers'].toString();
      }
    }
    if (artist == 'Unknown Artist') {
      artist = json['subtitle']?.toString() ??
          json['primary_artists']?.toString() ??
          json['singers']?.toString() ??
          json['artist']?.toString() ??
          'Unknown Artist';
    }

    // Album
    String? album = json['album']?.toString();
    if (album == null && moreInfo is Map) {
      album = (moreInfo as Map<String, dynamic>)['album']?.toString();
    }

    // Image
    String? albumArt = json['image']?.toString();
    if (albumArt == null && moreInfo is Map) {
      albumArt = (moreInfo as Map<String, dynamic>)['image']?.toString();
    }
    if (albumArt != null) {
      albumArt = albumArt
          .replaceAll('50x50', '500x500')
          .replaceAll('150x150', '500x500');
    }

    // Duration
    int dur = 0;
    if (moreInfo is Map) {
      dur = int.tryParse((moreInfo as Map<String, dynamic>)['duration']?.toString() ?? '') ?? 0;
    }
    if (dur == 0) {
      dur = int.tryParse(json['duration']?.toString() ?? '') ?? 0;
    }

    // Stream URL — decrypt encrypted_media_url
    String? previewUrl;
    String? encUrl;
    if (moreInfo is Map) {
      encUrl = (moreInfo as Map<String, dynamic>)['encrypted_media_url']?.toString();
    }
    encUrl ??= json['encrypted_media_url']?.toString();

    if (encUrl != null && encUrl.isNotEmpty) {
      previewUrl = _decrypt(encUrl);
    }

    final String? language = json['language']?.toString() ??
        (moreInfo is Map ? (moreInfo)['language']?.toString() : null);

    String finalArtist = _clean(artist).trim();
    if (finalArtist.isEmpty) finalArtist = 'Unknown Artist';

    return Song(
      id: id,
      title: title,
      artist: finalArtist,
      album: album != null ? _clean(album) : null,
      albumArt: albumArt,
      duration: Duration(seconds: dur),
      previewUrl: previewUrl,
      language: language,
    );
  }

  /// DES-ECB decrypt JioSaavn media URL (matches jiosaavn-api implementation)
  String _decrypt(String encryptedUrl, {bool upgradeTo320 = true}) {
    try {
      // DES key is '38346591' (8 bytes)
      // Use DESedeEngine with key repeated 3x = equivalent to single DES
      const keyStr = '38346591';
      final keyBytes = Uint8List.fromList(
        [...utf8.encode(keyStr), ...utf8.encode(keyStr), ...utf8.encode(keyStr)], // 24 bytes for 3DES
      );

      final cipher = ECBBlockCipher(DESedeEngine());
      cipher.init(false, KeyParameter(keyBytes)); // false = decrypt

      final input = Uint8List.fromList(base64.decode(encryptedUrl));
      final output = Uint8List(input.length);

      // Process each 8-byte block
      for (int offset = 0; offset < input.length; offset += 8) {
        cipher.processBlock(input, offset, output, offset);
      }

      // Remove PKCS7 padding
      final pad = output.last;
      final unpadded = (pad > 0 && pad <= 8)
          ? output.sublist(0, output.length - pad)
          : output;

      var url = utf8.decode(unpadded, allowMalformed: true);
      // Upgrade to HTTPS
      if (url.startsWith('http://')) {
        url = url.replaceFirst('http://', 'https://');
      }
      // Upgrade to 320kbps
      if (upgradeTo320) {
        return url.replaceAll('_96', '_320').replaceAll('_160', '_320');
      }
      return url;
    } catch (e) {
      debugPrint('[DirectJioSaavn] ⚠️ Decrypt failed: $e');
      return '';
    }
  }

  String _clean(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#039;', "'")
      .replaceAll('&nbsp;', ' ');

  /// Fetch a fresh stream URL for a song by its JioSaavn ID.
  ///
  /// JioSaavn CDN URLs are time-limited tokens that expire after a few minutes.
  /// When playback fails with "Source error", call this to get a valid URL.
  ///
  /// Response structure: { "songs": [ { "id": "...", "more_info": { "encrypted_media_url": "..." } } ], "modules": {...} }
  Future<String?> getFreshStreamUrl(String songId) async {
    if (songId.isEmpty) return null;
    debugPrint('[DirectJioSaavn] 🔄 Refreshing stream URL for song ID: $songId');
    try {
      final response = await _dio.get(
        _baseUrl,
        queryParameters: {
          '__call': 'song.getDetails',
          '_format': 'json',
          '_marker': '0',
          'api_version': '4',
          'ctx': 'web6dot0',
          'pids': songId,
        },
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = jsonDecode(response.data.toString()) as Map<String, dynamic>;

        // Response: { "songs": [ { "id": "...", "more_info": { "encrypted_media_url": "..." } } ] }
        final songsList = data['songs'] as List?;
        if (songsList != null && songsList.isNotEmpty) {
          final songData = songsList.first as Map<String, dynamic>?;
          if (songData != null) {
            final moreInfo = songData['more_info'] as Map<String, dynamic>?;
            final encUrl = moreInfo?['encrypted_media_url']?.toString()
                ?? songData['encrypted_media_url']?.toString();
            if (encUrl != null && encUrl.isNotEmpty) {
              final freshUrl = _decrypt(encUrl, upgradeTo320: false); // Fallback should use native bitrate
              if (freshUrl.isNotEmpty) {
                debugPrint('[DirectJioSaavn] ✅ Got fresh URL for $songId');
                return freshUrl;
              }
            }
          }
        }
        debugPrint('[DirectJioSaavn] ⚠️ No encrypted_media_url in song.getDetails response for $songId');
      }
    } catch (e) {
      debugPrint('[DirectJioSaavn] ❌ getFreshStreamUrl failed: $e');
    }
    return null;
  }


  void dispose() => _dio.close();
}
