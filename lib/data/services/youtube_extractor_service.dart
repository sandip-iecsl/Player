import 'dart:convert';
import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/song.dart';
import '../models/song_model.dart';
import '../models/youtube_audio_format.dart';

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

/// Result envelope for extracted YouTube playlists
class YouTubePlaylistResult {
  final String id;
  final String title;
  final String? channel;
  final String? thumbnailUrl;
  final int trackCount;
  final List<SongModel> tracks;

  const YouTubePlaylistResult({
    required this.id,
    required this.title,
    this.channel,
    this.thumbnailUrl,
    required this.trackCount,
    required this.tracks,
  });
}

class YouTubeSourceUnavailable implements Exception {
  final String requestedVideoId;
  final String category;
  final String message;

  const YouTubeSourceUnavailable({
    required this.requestedVideoId,
    required this.category,
    required this.message,
  });

  @override
  String toString() =>
      'YOUTUBE_SOURCE_UNAVAILABLE($requestedVideoId): $message';
}

/// Service responsible for communicating with the YouTube Extractor Microservice,
/// validating link formats, managing client-side metadata caching in Hive (yt_imports_cache),
/// and resolving multi-format audio streams (High ~320k, Medium ~128k, Data Saver ~64k).
class YouTubeExtractorService {
  static final YouTubeExtractorService _instance =
      YouTubeExtractorService._internal();
  factory YouTubeExtractorService() => _instance;
  YouTubeExtractorService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 25),
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  ));

  static const String cacheBoxName = 'yt_imports_cache_v2';
  String? _cachedWorkingEndpoint = 'https://player-wwrc.onrender.com';
  final Map<String, Future<YouTubeExtractionResult?>> _inFlightExtractions = {};

  static final RegExp _strictVideoIdRegex = RegExp(r'^[a-zA-Z0-9_\-]{11}$');

  static bool hasExactSourceIdentity(
      Map<String, dynamic> payload, String requestedVideoId) {
    return payload['source']?.toString() == 'youtube' &&
        payload['videoId']?.toString() == requestedVideoId &&
        payload['requestedVideoId']?.toString() == requestedVideoId;
  }

  /// Regex matching YouTube video URLs
  /// Permissive RegExp matching standard YouTube, YouTube Music, youtu.be, shorts, and embed URLs
  static final RegExp youtubeRegex = RegExp(
    r'^(https?:\/\/)?(www\.|music\.|m\.)?(youtube\.com\/(watch\?.*v=|shorts\/|live\/|v\/|embed\/|playlist\?)|youtu\.be\/)([a-zA-Z0-9_\-\?&=%#\.\+]+)$',
    caseSensitive: false,
  );

  /// Helper to sanitize and normalize YouTube URLs (Mix / Radio RD lists, tracking parameters, etc.)
  static String sanitizeYouTubeLink(String rawUrl) {
    try {
      final trimmed = rawUrl.trim();
      if (trimmed.isEmpty) return rawUrl;
      final uri = Uri.tryParse(
          trimmed.startsWith('http') ? trimmed : 'https://$trimmed');
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
      if (uri.path.contains('playlist') &&
          uri.queryParameters.containsKey('v')) {
        return 'https://www.youtube.com/watch?v=${uri.queryParameters['v']}';
      }

      // Rebuild standard URLs stripping tracking query params
      final cleanQueryParams = Map<String, String>.from(uri.queryParameters)
        ..remove('playnext')
        ..remove('si')
        ..remove('feature')
        ..remove('pp')
        ..remove('index')
        ..remove('start_radio');

      if (cleanQueryParams.isEmpty) {
        return uri.replace(query: '').toString();
      }
      return uri.replace(queryParameters: cleanQueryParams).toString();
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

  /// Checks if a string is a YouTube playlist URL
  static bool isPlaylistUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(
        trimmed.startsWith('http') ? trimmed : 'https://$trimmed');
    if (uri == null) return false;
    final list = uri.queryParameters['list'];
    if (list != null && list.startsWith('RD')) {
      return false;
    }
    if (list != null && list.isNotEmpty) {
      return true;
    }
    return uri.path.contains('playlist');
  }

  /// Extracts the playlist ID from a YouTube playlist URL
  static String? extractPlaylistId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(
        trimmed.startsWith('http') ? trimmed : 'https://$trimmed');
    if (uri != null) {
      final list = uri.queryParameters['list'];
      if (list != null && list.isNotEmpty && !list.startsWith('RD')) {
        return list;
      }
    }
    final match = RegExp(r'[?&]list=([a-zA-Z0-9_\-]+)').firstMatch(trimmed);
    if (match != null &&
        match.group(1) != null &&
        !match.group(1)!.startsWith('RD')) {
      return match.group(1);
    }
    return null;
  }

  /// Format duration into mm:ss or hh:mm:ss for long audio/video tracks
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${duration.inMinutes}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Checks if a string is a valid YouTube URL (video or playlist)
  static bool isYouTubeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    if (extractVideoId(trimmed) != null) return true;
    if (isPlaylistUrl(trimmed)) return true;
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
    final uri = Uri.tryParse(
        sanitized.startsWith('http') ? sanitized : 'https://$sanitized');
    if (uri != null) {
      // 1. Check v= query parameter
      final v = uri.queryParameters['v'];
      if (v != null && _strictVideoIdRegex.hasMatch(v)) {
        return v;
      }

      // 2. Check youtu.be/XXXXXXXXXXX
      if (uri.host.toLowerCase().contains('youtu.be') &&
          uri.pathSegments.isNotEmpty) {
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
    final match = RegExp(
            r'(?:watch\?v=|youtu\.be\/|shorts\/|embed\/|\/v\/)([a-zA-Z0-9_\-]{11})')
        .firstMatch(sanitized);
    if (match != null &&
        match.group(1) != null &&
        _strictVideoIdRegex.hasMatch(match.group(1)!)) {
      return match.group(1);
    }

    return null;
  }

  /// Selects the optimal audio format tier based on Wi-Fi connectivity and stream bitrate
  static Future<YouTubeAudioFormat> selectOptimalFormat(
      List<YouTubeAudioFormat> formats) async {
    if (formats.isEmpty) {
      return const YouTubeAudioFormat(
        quality: 'High',
        bitrate: '320 kbps',
        format: 'm4a',
        estimatedSizeMb: '12.5 MB',
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
          (f) =>
              f.formatId == '140' ||
              f.quality.toLowerCase() == 'high' ||
              f.bitrate.contains('320'),
          orElse: () => formats.first,
        );
      }
    } catch (_) {}

    return formats.first;
  }

  /// Candidate microservice endpoint URLs (Cloud Production URL + Local ADB fallbacks)
  List<String> get _candidateEndpoints {
    final list = <String>[];
    final envUrl = dotenv.env['YOUTUBE_EXTRACTOR_API_URL'];
    if (envUrl != null && envUrl.trim().isNotEmpty) {
      list.add(envUrl.trim().replaceAll(RegExp(r'\/$'), ''));
    }
    if (_cachedWorkingEndpoint != null) {
      list.add(_cachedWorkingEndpoint!);
    }
    list.add('https://player-wwrc.onrender.com'); // Live Cloud Production URL (Render)

    // Local fallbacks: Only query localhost on Desktop or Android Emulator
    if (!kIsWeb) {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        list.add('http://localhost:3000');
        list.add('http://127.0.0.1:3000');
      } else if (Platform.isAndroid && kDebugMode) {
        list.add('http://10.0.2.2:3000'); // Android Emulator fallback
      }
    }
    return list.toSet().toList();
  }

  /// Extracts YouTube playlist metadata and full list of tracks
  Future<YouTubePlaylistResult?> extractPlaylistWithTracks(
    String url, {
    int limit = 50,
  }) async {
    final trimmedUrl = url.trim();
    if (!isPlaylistUrl(trimmedUrl) && !isYouTubeUrl(trimmedUrl)) {
      return null;
    }
    final playlistId = extractPlaylistId(trimmedUrl) ?? trimmedUrl;

    debugPrint(
        '[YouTubeExtractor] 📋 Extracting YouTube playlist: $trimmedUrl (ID: $playlistId)');

    for (final ep in _candidateEndpoints) {
      try {
        final response = await _dio.post(
          '$ep/api/youtube/playlist',
          data: {'url': trimmedUrl, 'limit': limit},
        );

        if (response.statusCode == 200 && response.data != null) {
          final data = response.data is String
              ? jsonDecode(response.data)
              : response.data;
          final map = Map<String, dynamic>.from(data as Map);

          final tracksRaw = map['tracks'] as List? ?? [];
          final tracks = <SongModel>[];

          for (final t in tracksRaw) {
            if (t is Map) {
              final tMap = Map<String, dynamic>.from(t);
              final vid = tMap['id']?.toString() ?? '';
              if (vid.isEmpty) continue;

              final durationSec = (tMap['duration'] as num?)?.toInt() ?? 0;
              final trackUrl = tMap['url']?.toString() ??
                  'https://www.youtube.com/watch?v=$vid';

              tracks.add(SongModel(
                id: 'yt_$vid',
                title: tMap['title']?.toString() ?? 'YouTube Audio',
                artist: tMap['artist']?.toString() ??
                    map['channel']?.toString() ??
                    'YouTube',
                album: map['title']?.toString() ?? 'YouTube Playlist',
                albumArt: tMap['thumbnailUrl']?.toString() ??
                    'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
                duration: Duration(seconds: durationSec),
                previewUrl: null, // Resolved on-demand when played
                youtubeUrl: trackUrl,
                isYoutubeImport: true,
              ));
            }
          }

          if (tracks.isNotEmpty) {
            _cachedWorkingEndpoint = ep;
            return YouTubePlaylistResult(
              id: map['id']?.toString() ?? playlistId,
              title: map['title']?.toString() ?? 'YouTube Playlist',
              channel: map['channel']?.toString(),
              thumbnailUrl:
                  map['thumbnailUrl']?.toString() ?? tracks.first.albumArt,
              trackCount:
                  (map['trackCount'] as num?)?.toInt() ?? tracks.length,
              tracks: tracks,
            );
          }
        }
      } catch (e) {
        debugPrint('[YouTubeExtractor] ⚠️ Playlist query to $ep failed: $e');
      }
    }
    return null;
  }

  /// Legacy helper returning Song directly
  Future<Song?> extractTrack(String url, {bool forceRefresh = false}) async {
    final result =
        await extractTrackWithFormats(url, forceRefresh: forceRefresh);
    return result?.song;
  }

  /// Extracts YouTube track metadata along with standardized Multi-Format Quality Tiers
  Future<YouTubeExtractionResult?> extractTrackWithFormats(
    String url, {
    bool forceRefresh = false,
  }) async {
    final trimmedUrl = url.trim();
    if (isPlaylistUrl(trimmedUrl)) {
      final playlist = await extractPlaylistWithTracks(trimmedUrl, limit: 10);
      if (playlist != null && playlist.tracks.isNotEmpty) {
        final firstTrack = playlist.tracks.first;
        if (firstTrack.youtubeUrl != null) {
          return extractTrackWithFormats(firstTrack.youtubeUrl!,
              forceRefresh: forceRefresh);
        }
      }
    }

    final sanitizedUrl = enforceStrictVideoUrl(trimmedUrl);
    if (!isYouTubeUrl(trimmedUrl) && !isYouTubeUrl(sanitizedUrl)) {
      debugPrint('[YouTubeExtractor] ❌ Invalid YouTube URL: "$trimmedUrl"');
      return null;
    }

    final videoId = extractVideoId(sanitizedUrl) ?? extractVideoId(trimmedUrl);
    final cacheKey = videoId != null ? 'yt_v2_$videoId' : 'yt_v2_$sanitizedUrl';

    // 1. Check local Hive cache
    if (!forceRefresh) {
      final cachedResult = _getCachedResult(cacheKey);
      if (cachedResult != null &&
          videoId != null &&
          _isValidYouTubeResult(cachedResult, videoId)) {
        debugPrint(
            '[YouTubeExtractor] ⚡ Cache HIT for YouTube track: ${cachedResult.song.title}');
        return cachedResult;
      }
    }

    // 2. Deduplicate in-flight requests
    if (_inFlightExtractions.containsKey(cacheKey)) {
      debugPrint(
          '[YouTubeExtractor] ⏳ Reusing in-flight extraction for: $cacheKey');
      return _inFlightExtractions[cacheKey]!;
    }

    final future =
        _performExtractionWithFormats(sanitizedUrl, videoId, cacheKey);
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
    debugPrint(
        '[YouTubeExtractor] 🌐 Extracting YouTube stream formats for: $trimmedUrl (Video ID: $videoId)');

    // 1. Try cached working endpoint first
    if (_cachedWorkingEndpoint != null) {
      final res = await _queryEndpoint(
          _cachedWorkingEndpoint!, trimmedUrl, videoId, cacheKey);
      if (res != null) return res;
    }

    // 2. Parallel race across candidate endpoints
    final candidates = _candidateEndpoints
        .where((ep) => ep != _cachedWorkingEndpoint)
        .toList();
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

    // 3. Fallback Tier A: Query Decentralized Piped & Invidious Audio APIs
    if (videoId != null) {
      final pipedRes = await _tryPipedExtraction(videoId, trimmedUrl, cacheKey);
      if (pipedRes != null) {
        debugPrint(
            '[YouTubeExtractor] ⚡ Resolved via Piped/Invidious streaming for: ${pipedRes.song.title}');
        return pipedRes;
      }
    }

    if (videoId != null) {
      throw YouTubeSourceUnavailable(
        requestedVideoId: videoId,
        category: 'MEDIA_RESOLUTION_FAILED',
        message:
            'The requested YouTube recording is unavailable for playback or download.',
      );
    }
    return null;
  }

  /// Clean YouTube video title of emojis, hashtags, handles, and noise
  static String cleanVideoTitle(String rawTitle) {
    if (rawTitle.isEmpty) return 'YouTube Audio Track';
    return rawTitle
        .replaceAll(
            RegExp(
                r'[\u{1F300}-\u{1F9FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F600}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{1FA70}-\u{1FAFF}]|[\u{200D}\u{FE0F}]',
                unicode: true),
            '')
        .replaceAll(RegExp(r'#[\w\u0900-\u097F\u0980-\u09FF]+'), '')
        .replaceAll(RegExp(r'@[\w\u0900-\u097F\u0980-\u09FF_.]+'), '')
        .replaceAll(
            RegExp(
                r'\[\s*(Official\s*(Music\s*)?Video|Audio|HD|4K|Lyrics|Visualizer|Live|Full Song|Video Song|Audio Song|Video|Status|Bengali Status|WhatsApp Status|Lyrical)\s*\]',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'\(\s*(Official\s*(Music\s*)?Video|Audio|HD|4K|Lyrics|Visualizer|Live|Full Song|Video Song|Audio Song|Video|Status|Bengali Status|WhatsApp Status|Lyrical)\s*\)',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'\|\s*(Official\s*(Music\s*)?Video|Audio|HD|4K|Lyrics|Visualizer|Live|Full Song|Status|WhatsApp|Bengali).*$',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\|\|.*$'), '')
        .replaceAll(RegExp(r'【.*?】'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Extract core search terms for cross-engine resolution
  static String extractCleanQuery(String title, String? artist) {
    var cleaned = cleanVideoTitle(title);
    cleaned = cleaned
        .replaceAll(RegExp(r'\|.*$'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .trim();
    if (cleaned.contains(' - ')) {
      final parts = cleaned.split(' - ');
      return '${parts[0].trim()} ${parts[1].trim()}';
    }
    if (artist != null &&
        artist.isNotEmpty &&
        !cleaned.toLowerCase().contains(artist.toLowerCase())) {
      return '$cleaned $artist'.trim();
    }
    return cleaned;
  }

  /// Calculate token-based title similarity between 0.0 and 1.0
  static double calculateTitleSimilarity(String query, String candidateTitle) {
    if (query.isEmpty || candidateTitle.isEmpty) return 0.0;
    final qTokens = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0900-\u097F\u0980-\u09FF]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2)
        .toList();
    final cTokens = candidateTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0900-\u097F\u0980-\u09FF]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2)
        .toList();
    if (qTokens.isEmpty || cTokens.isEmpty) return 0.0;

    int matches = 0;
    for (final qt in qTokens) {
      if (cTokens.any((ct) => ct == qt || ct.contains(qt) || qt.contains(ct))) {
        matches++;
      }
    }
    return matches / qTokens.length;
  }

  /// Attempts to extract audio streams from public Piped and Invidious API instances
  Future<YouTubeExtractionResult?> _tryPipedExtraction(
    String videoId,
    String trimmedUrl,
    String cacheKey,
  ) async {
    final streamingInstances = [
      'https://pipedapi.leptons.xyz',
      'https://piped-api.lunar.icu',
      'https://api.piped.privacydev.net',
      'https://pipedapi.tokhmi.xyz',
      'https://inv.tux.pizza/api/v1/videos',
      'https://invidious.nerdvpn.de/api/v1/videos',
    ];

    for (final instance in streamingInstances) {
      try {
        final isPiped = instance.contains('piped');
        final endpoint =
            isPiped ? '$instance/streams/$videoId' : '$instance/$videoId';

        final res = await _dio.get(
          endpoint,
          options: Options(
            receiveTimeout: const Duration(seconds: 8),
            connectTimeout: const Duration(seconds: 6),
          ),
        );

        if (res.statusCode == 200 && res.data != null) {
          final data = res.data is String ? jsonDecode(res.data) : res.data;
          final title =
              cleanVideoTitle(data['title']?.toString() ?? 'YouTube Audio');
          final uploader = data['uploader']?.toString() ??
              data['author']?.toString() ??
              'YouTube Artist';
          final durationSec = (data['duration'] as num?)?.toInt() ??
              (data['lengthSeconds'] as num?)?.toInt() ??
              0;
          final audioStreams = (data['audioStreams'] as List?) ??
              (data['adaptiveFormats'] as List?)
                  ?.where((f) =>
                      f['type']?.toString().startsWith('audio/') ?? false)
                  .toList();

          if (audioStreams != null && audioStreams.isNotEmpty) {
            final formats = <YouTubeAudioFormat>[];
            for (final st in audioStreams) {
              final streamUrl = st['url']?.toString();
              if (streamUrl != null && streamUrl.isNotEmpty) {
                final abr = (st['bitrate'] as num?)?.toDouble() ?? 160000;
                final bitrateStr = '${(abr / 1000).round()} kbps';
                final formatStr = (st['format']?.toString() ??
                        st['container']?.toString() ??
                        'm4a')
                    .toLowerCase()
                    .replaceAll('webm', 'opus');
                final quality = abr >= 160000
                    ? 'High'
                    : (abr >= 100000 ? 'Medium' : 'Data Saver');

                formats.add(YouTubeAudioFormat(
                  quality: quality,
                  bitrate: bitrateStr,
                  format: formatStr,
                  estimatedSizeMb: YouTubeAudioFormat.estimateSizeMb(
                      abr / 1000, durationSec),
                  streamUrl: streamUrl,
                  formatId: st['format']?.toString() ??
                      st['itag']?.toString() ??
                      '140',
                ));
              }
            }

            if (formats.isNotEmpty) {
              final optimalFormat = await selectOptimalFormat(formats);
              final songModel = SongModel(
                id: 'yt_$videoId',
                title: title,
                artist: uploader,
                album: 'YouTube Imports',
                albumArt: data['thumbnailUrl'] ??
                    'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
                duration: Duration(seconds: durationSec),
                previewUrl: optimalFormat.streamUrl,
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
              await _cacheResult(cacheKey, result);
              return result;
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Builds direct binary download URL with formatId or quality parameters
  String getDownloadUrl(
    Song song, {
    String? formatId,
    String? quality,
  }) {
    final videoId = extractVideoId(song.youtubeUrl ?? '') ??
        song.id.replaceFirst('yt_', '');
    final cleanTitle = Uri.encodeComponent(song.title);
    final baseUrl = _cachedWorkingEndpoint ?? _candidateEndpoints.first;

    final sourceUrl = enforceStrictVideoUrl(song.youtubeUrl ?? '');
    final encodedSource = Uri.encodeQueryComponent(
      sourceUrl.isNotEmpty
          ? sourceUrl
          : 'https://www.youtube.com/watch?v=$videoId',
    );
    var url =
        '$baseUrl/api/youtube/download?url=$encodedSource&title=$cleanTitle';
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
    final rawUrl = song.youtubeUrl ??
        (song.id.startsWith('yt_')
            ? 'https://www.youtube.com/watch?v=${song.id.replaceFirst('yt_', '')}'
            : null);
    if (rawUrl == null) return null;

    final freshResult =
        await extractTrackWithFormats(rawUrl, forceRefresh: true);
    return freshResult?.selectedFormat.streamUrl ??
        freshResult?.song.previewUrl;
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
        final data =
            response.data is String ? jsonDecode(response.data) : response.data;
        final map = Map<String, dynamic>.from(data as Map);

        if (!hasExactSourceIdentity(map, videoId ?? '')) {
          debugPrint(
              '[YouTubeExtractor] ⚠️ Rejected endpoint response with wrong source identity for $videoId');
          return null;
        }

        final formatsList = <YouTubeAudioFormat>[];
        if (map['availableFormats'] is List) {
          for (final f in map['availableFormats']) {
            if (f is Map) {
              formatsList.add(
                  YouTubeAudioFormat.fromJson(Map<String, dynamic>.from(f)));
            }
          }
        }

        final streamUrl = map['streamUrl']?.toString() ??
            (formatsList.isNotEmpty ? formatsList.first.streamUrl : '');

        if (streamUrl.isNotEmpty || formatsList.isNotEmpty) {
          if (formatsList.isEmpty) {
            debugPrint(
                '[YouTubeExtractor] ⚠️ Rejected endpoint response without verified media formats');
            return null;
          }
          final durationSec = (map['duration'] as num?)?.toInt() ?? 0;
          final finalFormats = formatsList;

          final selectedFormat = await selectOptimalFormat(finalFormats);

          final songModel = SongModel(
            id: map['id']?.toString() ??
                'yt_${videoId ?? DateTime.now().millisecondsSinceEpoch}',
            title: map['title']?.toString() ?? 'YouTube Audio',
            artist: map['artist']?.toString() ?? 'YouTube Channel',
            album: map['album']?.toString() ?? 'YouTube Imports',
            albumArt: map['thumbnailUrl']?.toString() ??
                (videoId != null
                    ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg'
                    : null),
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

          if (!_isValidYouTubeResult(result, videoId!)) return null;
          _cachedWorkingEndpoint = endpoint;
          await _cacheResult(cacheKey, result);

          debugPrint(
              '[YouTubeExtractor] ✅ Successfully extracted via $endpoint: "${songModel.title}" (${finalFormats.length} formats, Selected: ${selectedFormat.quality} / ${selectedFormat.bitrate})');
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
        if (map['source']?.toString() != 'youtube' || map['videoId'] == null) {
          return null;
        }
        final song = SongModel.fromJson(map);
        final formats = <YouTubeAudioFormat>[];
        if (map['availableFormats'] is List) {
          for (final f in map['availableFormats']) {
            if (f is Map) {
              formats.add(
                  YouTubeAudioFormat.fromJson(Map<String, dynamic>.from(f)));
            }
          }
        }
        if (formats.isEmpty) return null;
        final finalFormats = formats;

        final selected = finalFormats.firstWhere(
          (f) =>
              f.formatId == song.formatId ||
              (song.formatId != null && f.formatId.contains(song.formatId!)),
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

  bool _isValidYouTubeResult(YouTubeExtractionResult result, String videoId) {
    final song = result.song;
    final urlVideoId = extractVideoId(song.youtubeUrl ?? '');
    return song.id == 'yt_$videoId' &&
        urlVideoId == videoId &&
        song.isYoutubeImport &&
        song.previewUrl != null &&
        song.previewUrl!.isNotEmpty &&
        result.availableFormats.any((format) => format.streamUrl.isNotEmpty);
  }

  Future<void> _cacheResult(
      String cacheKey, YouTubeExtractionResult result) async {
    try {
      if (!Hive.isBoxOpen(cacheBoxName)) {
        await Hive.openBox(cacheBoxName);
      }
      final box = Hive.box(cacheBoxName);
      final map = {
        ...result.song.toJson(),
        'source': 'youtube',
        'videoId': extractVideoId(result.song.youtubeUrl ?? ''),
        'mediaState': 'MediaResolved',
        'availableFormats':
            result.availableFormats.map((f) => f.toJson()).toList(),
      };
      await box.put(cacheKey, map);
    } catch (e) {
      debugPrint('[YouTubeExtractor] ⚠️ Cache write error: $e');
    }
  }
}
