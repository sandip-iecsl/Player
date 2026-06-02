import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
  Future<List<Song>> searchSongs(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];

    debugPrint('[DirectJioSaavn] 🔍 Searching for: "$query"');

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
          'p': '1',
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
      artist = json['primary_artists']?.toString() ??
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

    return Song(
      id: id,
      title: title,
      artist: _clean(artist),
      album: album != null ? _clean(album) : null,
      albumArt: albumArt,
      duration: Duration(seconds: dur),
      previewUrl: previewUrl,
    );
  }

  /// DES-ECB decrypt JioSaavn media URL (matches jiosaavn-api implementation)
  String _decrypt(String encryptedUrl) {
    try {
      // DES key is '38346591' (8 bytes)
      // Use DESedeEngine with key repeated 3x = equivalent to single DES
      final keyStr = '38346591';
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

      final url = utf8.decode(unpadded, allowMalformed: true);
      // Upgrade to 320kbps
      return url.replaceAll('_96', '_320').replaceAll('_160', '_320');
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

  void dispose() => _dio.close();
}
