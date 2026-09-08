import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/song.dart';
import '../models/song_model.dart';
import '../models/youtube_audio_format.dart';
import 'direct_jiosaavn_service.dart';

/// Result envelope containing both the extracted Song and its available quality tiers
class YouTubeExtractionResult {
  final SongModel song;
  final List<YouTubeAudioFormat> availableFormats;
  final YouTubeAudioFormat selectedFormat;

  const YouTubeExtractionResult({
    required this.song,
    required this.availableFormats,
    required this.selectedFormat,
  });
}

/// Service responsible for communicating with the YouTube Extractor Microservice,
/// validating link formats, managing client-side metadata caching in Hive (yt_imports_cache),
/// and resolving multi-format audio streams (High ~320k, Medium ~128k, Data Saver ~64k).
class YouTubeExtractorService {
  static final YouTubeExtractorService _instance = YouTubeExtractorService._internal();
  factory YouTubeExtractorService() => _instance;
  YouTubeExtractorService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
  ));

  static const String cacheBoxName = 'yt_imports_cache';
  String? _cachedWorkingEndpoint = 'https://player-wwrc.onrender.com';
  final Map<String, Future<YouTubeExtractionResult?>> _inFlightExtractions = {};

  /// Regex matching YouTube video URLs
  static final RegExp youtubeRegex = RegExp(
    r'^(https?:\/\/)?(www\.|music\.)?(youtube\.com\/(watch\?v=|shorts\/|v\/|embed\/)|youtu\.be\/)([a-zA-Z0-9_\-]{11})([^\s]*)$',
    caseSensitive: false,
  );

  /// Checks if a string is a valid YouTube URL
  static bool isYouTubeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    return youtubeRegex.hasMatch(trimmed);
  }

  /// Extracts the 11-character video ID from a YouTube URL
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    final match = youtubeRegex.firstMatch(trimmed);
    if (match != null && match.groupCount >= 5) {
      return match.group(5);
    }
    return null;
  }

  /// Candidate microservice endpoint URLs (Cloud Production URL + Local ADB fallbacks)
  List<String> get _candidateEndpoints {
    final list = <String>[];
    if (_cachedWorkingEndpoint != null) {
      list.add(_cachedWorkingEndpoint!);
    }
    final envUrl = dotenv.env['YOUTUBE_EXTRACTOR_API_URL'];
    if (envUrl != null && envUrl.trim().isNotEmpty) {
      list.add(envUrl.trim().replaceAll(RegExp(r'\/$'), ''));
    }
    list.addAll([
      'https://player-wwrc.onrender.com',    // Live Cloud Production URL (Render)
      'http://localhost:3000',               // Local ADB fallback
      'http://127.0.0.1:3000',
      'http://10.0.2.2:3000',               // Android Emulator fallback
    ]);
    return list.toSet().toList();
  }

  /// Legacy helper returning Song directly
  Future<Song?> extractTrack(String url, {bool forceRefresh = false}) async {
    final result = await extractTrackWithFormats(url, forceRefresh: forceRefresh);
    return result?.song;
  }

  /// Extracts YouTube track metadata along with standardized Multi-Format Quality Tiers
  Future<YouTubeExtractionResult?> extractTrackWithFormats(
    String url, {
    bool forceRefresh = false,
  }) async {
    final trimmedUrl = url.trim();
    if (!isYouTubeUrl(trimmedUrl)) {
      debugPrint('[YouTubeExtractor] ❌ Invalid YouTube URL: "$trimmedUrl"');
      return null;
    }

    final videoId = extractVideoId(trimmedUrl);
    final cacheKey = videoId != null ? 'yt_$videoId' : trimmedUrl;

    // 1. Check local Hive cache
    if (!forceRefresh) {
      final cachedResult = _getCachedResult(cacheKey);
      if (cachedResult != null && cachedResult.song.previewUrl != null && cachedResult.song.previewUrl!.isNotEmpty) {
        debugPrint('[YouTubeExtractor] ⚡ Cache HIT for YouTube track: ${cachedResult.song.title}');
        return cachedResult;
      }
    }

    // 2. Deduplicate in-flight requests
    if (_inFlightExtractions.containsKey(cacheKey)) {
      debugPrint('[YouTubeExtractor] ⏳ Reusing in-flight extraction for: $cacheKey');
      return _inFlightExtractions[cacheKey]!;
    }

    final future = _performExtractionWithFormats(trimmedUrl, videoId, cacheKey);
    _inFlightExtractions[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _inFlightExtractions.remove(cacheKey);
    }
  }

  Future<YouTubeExtractionResult?> _performExtractionWithFormats(
    String trimmedUrl,
    String? videoId,
    String cacheKey,
  ) async {
    debugPrint('[YouTubeExtractor] 🌐 Extracting YouTube stream formats for: $trimmedUrl (Video ID: $videoId)');

    // 1. Try cached working endpoint first
    if (_cachedWorkingEndpoint != null) {
      final res = await _queryEndpoint(_cachedWorkingEndpoint!, trimmedUrl, videoId, cacheKey);
      if (res != null) return res;
    }

    // 2. Parallel race across candidate endpoints
    final candidates = _candidateEndpoints.where((ep) => ep != _cachedWorkingEndpoint).toList();
    if (candidates.isNotEmpty) {
      try {
        final res = await Future.any(candidates.map((ep) async {
          final r = await _queryEndpoint(ep, trimmedUrl, videoId, cacheKey);
          if (r != null) return r;
          throw Exception('Endpoint $ep returned null');
        }));
        return res;
      } catch (_) {}
    }

    // 3. Fallback: Query YouTube oEmbed API + JioSaavn / Direct Stream search
    if (videoId != null) {
      debugPrint('[YouTubeExtractor] 🛡️ Falling back to YouTube oEmbed + audio resolution for video: $videoId');
      try {
        final oembedRes = await _dio.get(
          'https://www.youtube.com/oembed',
          queryParameters: {'url': 'https://www.youtube.com/watch?v=$videoId', 'format': 'json'},
        );

        if (oembedRes.statusCode == 200 && oembedRes.data != null) {
          final data = oembedRes.data is String ? jsonDecode(oembedRes.data) : oembedRes.data;
          final oembedMap = Map<String, dynamic>.from(data as Map);
          final rawTitle = oembedMap['title']?.toString() ?? 'YouTube Audio';
          final authorName = oembedMap['author_name']?.toString() ?? 'YouTube Channel';

          final cleanTitle = rawTitle
              .replaceAll(RegExp(r'\[.*?\]'), '')
              .replaceAll(RegExp(r'\(.*?\)'), '')
              .replaceAll(RegExp(r'\|.*$'), '')
              .trim();

          var searchQuery = cleanTitle.replaceAll(RegExp(r'\s*(mashup|mix|remix|edit|ft\.|feat\.).*$', caseSensitive: false), '').trim();
          if (searchQuery.isEmpty) searchQuery = cleanTitle;

          String? streamUrl;
          try {
            debugPrint('[YouTubeExtractor] 🔍 Searching JioSaavn fallback for: "$searchQuery"');
            final searchResults = await DirectJioSaavnService().searchSongs(searchQuery, limit: 5);
            if (searchResults.isNotEmpty) {
              final matched = searchResults.firstWhere(
                (s) => s.previewUrl != null && s.previewUrl!.isNotEmpty,
                orElse: () => searchResults.first,
              );
              streamUrl = matched.previewUrl;
              debugPrint('[YouTubeExtractor] 🎯 Found JioSaavn stream: $streamUrl');
            }
          } catch (searchErr) {
            debugPrint('[YouTubeExtractor] ⚠️ JioSaavn fallback search error: $searchErr');
          }

          const duration = Duration(seconds: 210);
          final formats = streamUrl != null
              ? YouTubeAudioFormat.defaults(streamUrl: streamUrl, durationSec: duration.inSeconds)
              : <YouTubeAudioFormat>[];

          final songModel = SongModel(
            id: 'yt_$videoId',
            title: cleanTitle.isNotEmpty ? cleanTitle : rawTitle,
            artist: authorName,
            album: 'YouTube Imports',
            albumArt: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
            duration: duration,
            previewUrl: streamUrl,
            youtubeUrl: trimmedUrl,
            isYoutubeImport: true,
            bitrate: formats.isNotEmpty ? formats.first.bitrate : '320 kbps',
            formatId: formats.isNotEmpty ? formats.first.formatId : '140',
          );

          final result = YouTubeExtractionResult(
            song: songModel,
            availableFormats: formats,
            selectedFormat: formats.isNotEmpty
                ? formats.first
                : YouTubeAudioFormat(
                    quality: 'High',
                    bitrate: '320 kbps',
                    format: 'm4a',
                    estimatedSizeMb: '8.5 MB',
                    streamUrl: streamUrl ?? '',
                    formatId: '140',
                  ),
          );

          if (streamUrl != null && streamUrl.isNotEmpty) {
            await _cacheResult(cacheKey, result);
          }
          return result;
        }
      } catch (fallbackErr) {
        debugPrint('[YouTubeExtractor] ❌ Fallback oEmbed failed: $fallbackErr');
      }
    }

    return null;
  }

  /// Builds direct binary download URL with formatId or quality parameters
  String getDownloadUrl(
    Song song, {
    String? formatId,
    String? quality,
  }) {
    final videoId = extractVideoId(song.youtubeUrl ?? '') ?? song.id.replaceFirst('yt_', '');
    final cleanTitle = Uri.encodeComponent(song.title);
    final baseUrl = _cachedWorkingEndpoint ?? _candidateEndpoints.first;

    var url = '$baseUrl/api/youtube/download?id=$videoId&title=$cleanTitle';
    if (formatId != null && formatId.isNotEmpty) {
      url += '&formatId=$formatId';
    }
    if (quality != null && quality.isNotEmpty) {
      url += '&quality=${Uri.encodeComponent(quality)}';
    }
    return url;
  }

  /// Refreshes an expired stream URL for a given YouTube song
  Future<String?> getFreshStreamUrl(Song song) async {
    final rawUrl = song.youtubeUrl ?? (song.id.startsWith('yt_') ? 'https://www.youtube.com/watch?v=${song.id.replaceFirst('yt_', '')}' : null);
    if (rawUrl == null) return null;

    final freshResult = await extractTrackWithFormats(rawUrl, forceRefresh: true);
    return freshResult?.selectedFormat.streamUrl ?? freshResult?.song.previewUrl;
  }

  Future<YouTubeExtractionResult?> _queryEndpoint(
    String endpoint,
    String trimmedUrl,
    String? videoId,
    String cacheKey,
  ) async {
    try {
      debugPrint('[YouTubeExtractor] 🔄 Querying microservice at: $endpoint');
      final response = await _dio.post(
        '$endpoint/api/youtube/extract',
        data: {'url': trimmedUrl},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String ? jsonDecode(response.data) : response.data;
        final map = Map<String, dynamic>.from(data as Map);

        final formatsList = <YouTubeAudioFormat>[];
        if (map['availableFormats'] is List) {
          for (final f in map['availableFormats']) {
            if (f is Map) {
              formatsList.add(YouTubeAudioFormat.fromJson(Map<String, dynamic>.from(f)));
            }
          }
        }

        final streamUrl = map['streamUrl']?.toString() ?? (formatsList.isNotEmpty ? formatsList.first.streamUrl : '');

        if (streamUrl.isNotEmpty || formatsList.isNotEmpty) {
          // If availableFormats wasn't provided by backend, generate standard 3-tier defaults
          final durationSec = (map['duration'] as num?)?.toInt() ?? 180;
          final finalFormats = formatsList.isNotEmpty
              ? formatsList
              : YouTubeAudioFormat.defaults(streamUrl: streamUrl, durationSec: durationSec);

          final selectedFormat = finalFormats.first;

          final songModel = SongModel(
            id: map['id']?.toString() ?? 'yt_${videoId ?? DateTime.now().millisecondsSinceEpoch}',
            title: map['title']?.toString() ?? 'YouTube Audio',
            artist: map['artist']?.toString() ?? 'YouTube Channel',
            album: map['album']?.toString() ?? 'YouTube Imports',
            albumArt: map['thumbnailUrl']?.toString() ?? (videoId != null ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg' : null),
            duration: Duration(seconds: durationSec),
            previewUrl: selectedFormat.streamUrl,
            youtubeUrl: trimmedUrl,
            isYoutubeImport: true,
            bitrate: selectedFormat.bitrate,
            formatId: selectedFormat.formatId,
          );

          final result = YouTubeExtractionResult(
            song: songModel,
            availableFormats: finalFormats,
            selectedFormat: selectedFormat,
          );

          _cachedWorkingEndpoint = endpoint;
          await _cacheResult(cacheKey, result);

          debugPrint('[YouTubeExtractor] ✅ Successfully extracted via $endpoint: "${songModel.title}" (${finalFormats.length} formats)');
          return result;
        }
      }
    } catch (e) {
      debugPrint('[YouTubeExtractor] ⚠️ Endpoint $endpoint failed: $e');
    }
    return null;
  }

  // ── Hive Cache Management ──────────────────────────────────────────────────

  YouTubeExtractionResult? _getCachedResult(String cacheKey) {
    try {
      if (!Hive.isBoxOpen(cacheBoxName)) return null;
      final box = Hive.box(cacheBoxName);
      final rawData = box.get(cacheKey);
      if (rawData != null) {
        final map = Map<String, dynamic>.from(rawData as Map);
        final song = SongModel.fromJson(map);
        final formats = <YouTubeAudioFormat>[];
        if (map['availableFormats'] is List) {
          for (final f in map['availableFormats']) {
            if (f is Map) {
              formats.add(YouTubeAudioFormat.fromJson(Map<String, dynamic>.from(f)));
            }
          }
        }
        final finalFormats = formats.isNotEmpty
            ? formats
            : YouTubeAudioFormat.defaults(streamUrl: song.previewUrl ?? '', durationSec: song.duration.inSeconds);

        return YouTubeExtractionResult(
          song: song,
          availableFormats: finalFormats,
          selectedFormat: finalFormats.first,
        );
      }
    } catch (e) {
      debugPrint('[YouTubeExtractor] ⚠️ Cache read error: $e');
    }
    return null;
  }

  Future<void> _cacheResult(String cacheKey, YouTubeExtractionResult result) async {
    try {
      if (!Hive.isBoxOpen(cacheBoxName)) {
        await Hive.openBox(cacheBoxName);
      }
      final box = Hive.box(cacheBoxName);
      final map = {
        ...result.song.toJson(),
        'availableFormats': result.availableFormats.map((f) => f.toJson()).toList(),
      };
      await box.put(cacheKey, map);
    } catch (e) {
      debugPrint('[YouTubeExtractor] ⚠️ Cache write error: $e');
    }
  }
}
