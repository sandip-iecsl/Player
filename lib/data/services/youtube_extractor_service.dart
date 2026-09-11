import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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

  static final RegExp _strictVideoIdRegex = RegExp(r'^[a-zA-Z0-9_\-]{11}$');

  /// Regex matching YouTube video URLs
  static final RegExp youtubeRegex = RegExp(
    r'^(https?:\/\/)?(www\.|music\.)?(youtube\.com\/(watch\?v=|shorts\/|v\/|embed\/|playlist\?)|youtu\.be\/)([a-zA-Z0-9_\-\?&=]+)$',
    caseSensitive: false,
  );

  /// Helper to sanitize and normalize YouTube URLs (Mix / Radio RD lists, tracking parameters, etc.)
  static String sanitizeYouTubeLink(String rawUrl) {
    try {
      final trimmed = rawUrl.trim();
      if (trimmed.isEmpty) return rawUrl;
      final uri = Uri.tryParse(trimmed.startsWith('http') ? trimmed : 'https://$trimmed');
      if (uri == null) return trimmed;

      final listParam = uri.queryParameters['list'];

      // Handle dynamic Mix / Radio playlists (list=RD...)
      if (listParam != null && listParam.startsWith('RD')) {
        String? videoId = uri.queryParameters['v'];
        if (videoId == null || videoId.isEmpty) {
          // Extract video ID embedded in list ID: RD_JL6JAf-HKw -> _JL6JAf-HKw, RDCLkA2bX4x18 -> CLkA2bX4x18
          videoId = listParam.replaceFirst(RegExp(r'^(RDMM|RDCL|RD)'), '');
        }
        return 'https://www.youtube.com/watch?v=$videoId&list=$listParam';
      }

      // If it's a playlist URL with a specific 'v' parameter
      if (uri.path.contains('playlist') && uri.queryParameters.containsKey('v')) {
        return 'https://www.youtube.com/watch?v=${uri.queryParameters['v']}';
      }

      // Rebuild standard URLs stripping tracking query params
      final cleanQueryParams = Map<String, String>.from(uri.queryParameters)
        ..remove('playnext')
        ..remove('si')
        ..remove('feature')
        ..remove('pp')
        ..remove('index');

      return uri.replace(queryParameters: cleanQueryParams.isNotEmpty ? cleanQueryParams : null).toString();
    } catch (_) {
      return rawUrl.trim();
    }
  }

  /// Returns a canonical watch URL only when the input contains an exact
  /// YouTube video ID. Playlist and search-like URLs are never guessed here.
  static String enforceStrictVideoUrl(String inputUrl) {
    final videoId = extractVideoId(inputUrl);
    if (videoId != null && _strictVideoIdRegex.hasMatch(videoId)) {
      return 'https://www.youtube.com/watch?v=$videoId';
    }
    return inputUrl.trim();
  }

  /// Checks if a string is a valid YouTube URL
  static bool isYouTubeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    if (extractVideoId(trimmed) != null) return true;
    if (youtubeRegex.hasMatch(trimmed)) return true;
    final sanitized = sanitizeYouTubeLink(trimmed);
    return youtubeRegex.hasMatch(sanitized);
  }

  /// Extracts the strict 11-character video ID from any YouTube URL (watch, youtu.be, shorts, embed, mix)
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    if (_strictVideoIdRegex.hasMatch(trimmed)) {
      return trimmed;
    }

    final sanitized = sanitizeYouTubeLink(trimmed);
    final uri = Uri.tryParse(sanitized.startsWith('http') ? sanitized : 'https://$sanitized');
    if (uri != null) {
      // 1. Check v= query parameter
      final v = uri.queryParameters['v'];
      if (v != null && _strictVideoIdRegex.hasMatch(v)) {
        return v;
      }

      // 2. Check youtu.be/XXXXXXXXXXX
      if (uri.host.toLowerCase().contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        final seg = uri.pathSegments.first;
        if (_strictVideoIdRegex.hasMatch(seg)) {
          return seg;
        }
      }

      // 3. Check /shorts/XXXXXXXXXXX
      final shortsIdx = uri.pathSegments.indexOf('shorts');
      if (shortsIdx >= 0 && shortsIdx + 1 < uri.pathSegments.length) {
        final seg = uri.pathSegments[shortsIdx + 1];
        if (_strictVideoIdRegex.hasMatch(seg)) {
          return seg;
        }
      }

      // 4. Check /embed/XXXXXXXXXXX or /v/XXXXXXXXXXX
      final embedIdx = uri.pathSegments.indexOf('embed');
      if (embedIdx >= 0 && embedIdx + 1 < uri.pathSegments.length) {
        final seg = uri.pathSegments[embedIdx + 1];
        if (_strictVideoIdRegex.hasMatch(seg)) {
          return seg;
        }
      }
      final vIdx = uri.pathSegments.indexOf('v');
      if (vIdx >= 0 && vIdx + 1 < uri.pathSegments.length) {
        final seg = uri.pathSegments[vIdx + 1];
        if (_strictVideoIdRegex.hasMatch(seg)) {
          return seg;
        }
      }

      // 5. Dynamic Mix RD list ID fallback (e.g. list=RD_JL6JAf-HKw)
      final listParam = uri.queryParameters['list'];
      if (listParam != null && listParam.startsWith('RD')) {
        final rdId = listParam.replaceFirst(RegExp(r'^(RDMM|RDCL|RD)'), '');
        if (_strictVideoIdRegex.hasMatch(rdId)) {
          return rdId;
        }
      }
    }

    // RegEx matchers fallback
    final match = RegExp(r'(?:watch\?v=|youtu\.be\/|shorts\/|embed\/|\/v\/)([a-zA-Z0-9_\-]{11})').firstMatch(sanitized);
    if (match != null && match.group(1) != null && _strictVideoIdRegex.hasMatch(match.group(1)!)) {
      return match.group(1);
    }

    return null;
  }

  /// Selects the optimal audio format tier based on Wi-Fi connectivity and stream bitrate
  static Future<YouTubeAudioFormat> selectOptimalFormat(List<YouTubeAudioFormat> formats) async {
    if (formats.isEmpty) {
      return const YouTubeAudioFormat(
        quality: 'High',
        bitrate: '320 kbps',
        format: 'm4a',
        estimatedSizeMb: '8.5 MB',
        streamUrl: '',
        formatId: '140',
      );
    }

    try {
      final connectivity = await Connectivity().checkConnectivity();
      final isWifi = connectivity.contains(ConnectivityResult.wifi) ||
                     connectivity.contains(ConnectivityResult.ethernet);

      if (isWifi) {
        // High Quality tier: formatId 140 (AAC/m4a ~320k) or highest bitrate tier
        return formats.firstWhere(
          (f) => f.formatId == '140' || f.quality.toLowerCase() == 'high' || f.bitrate.contains('320'),
          orElse: () => formats.first,
        );
      }
    } catch (_) {}

    return formats.first;
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
    final sanitizedUrl = enforceStrictVideoUrl(trimmedUrl);
    if (!isYouTubeUrl(trimmedUrl) && !isYouTubeUrl(sanitizedUrl)) {
      debugPrint('[YouTubeExtractor] ❌ Invalid YouTube URL: "$trimmedUrl"');
      return null;
    }

    final videoId = extractVideoId(sanitizedUrl) ?? extractVideoId(trimmedUrl);
    final cacheKey = videoId != null ? 'yt_$videoId' : sanitizedUrl;

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

    final future = _performExtractionWithFormats(sanitizedUrl, videoId, cacheKey);
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

          final optimalFormat = await selectOptimalFormat(formats);

          final songModel = SongModel(
            id: 'yt_$videoId',
            title: cleanTitle.isNotEmpty ? cleanTitle : rawTitle,
            artist: authorName,
            album: 'YouTube Imports',
            albumArt: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
            duration: duration,
            previewUrl: optimalFormat.streamUrl.isNotEmpty ? optimalFormat.streamUrl : streamUrl,
            youtubeUrl: trimmedUrl,
            isYoutubeImport: true,
            bitrate: optimalFormat.bitrate,
            formatId: optimalFormat.formatId,
          );

          final result = YouTubeExtractionResult(
            song: songModel,
            availableFormats: formats,
            selectedFormat: optimalFormat,
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

    final sourceUrl = enforceStrictVideoUrl(song.youtubeUrl ?? '');
    final encodedSource = Uri.encodeQueryComponent(
      sourceUrl.isNotEmpty ? sourceUrl : 'https://www.youtube.com/watch?v=$videoId',
    );
    var url = '$baseUrl/api/youtube/download?url=$encodedSource&title=$cleanTitle';
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

          final selectedFormat = await selectOptimalFormat(finalFormats);

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

          debugPrint('[YouTubeExtractor] ✅ Successfully extracted via $endpoint: "${songModel.title}" (${finalFormats.length} formats, Selected: ${selectedFormat.quality} / ${selectedFormat.bitrate})');
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

        final selected = finalFormats.firstWhere(
          (f) => f.formatId == song.formatId || (song.formatId != null && f.formatId.contains(song.formatId!)),
          orElse: () => finalFormats.first,
        );

        return YouTubeExtractionResult(
          song: song,
          availableFormats: finalFormats,
          selectedFormat: selected,
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
