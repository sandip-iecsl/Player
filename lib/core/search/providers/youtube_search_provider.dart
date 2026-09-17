import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/search_models.dart';
import 'provider_health.dart';
import 'search_provider.dart';

/// Provider 6: YouTube Discovery & Search via Backend API Proxy
/// Keeps API keys server-side and queries /api/search/youtube
class YouTubeSearchProvider implements SearchProviderClient {
  @override
  final SearchProviderType provider = SearchProviderType.youtube;

  @override
  final ProviderHealth health = ProviderHealth(provider: SearchProviderType.youtube);

  @override
  bool get isEnabled => true;

  @override
  int get priority => 6;

  @override
  Duration get timeout => const Duration(seconds: 6);

  final Dio _dio;

  YouTubeSearchProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
              headers: {
                'User-Agent': 'AuraPlayer/2.0 (Mobile; Android/iOS)',
                'Accept': 'application/json',
              },
            ));

  String get _backendUrl {
    final configured = dotenv.env['YOUTUBE_EXTRACTOR_URL']?.trim();
    if (configured != null && configured.isNotEmpty) {
      return configured.endsWith('/') ? configured.substring(0, configured.length - 1) : configured;
    }
    return 'http://127.0.0.1:3000';
  }

  @override
  Future<List<SearchCandidate>> search(
    ParsedQuery query,
    SearchRequest request,
  ) async {
    if (!health.isAvailable) {
      debugPrint('[YouTubeSearchProvider] ⚡ Circuit OPEN. Skipping request.');
      return [];
    }

    final stopwatch = Stopwatch()..start();
    try {
      final q = query.effectiveQuery;
      final endpoint = '$_backendUrl/api/search/youtube';

      final response = await _dio.get(
        endpoint,
        queryParameters: {
          'q': q,
          'limit': request.limit,
        },
      ).timeout(timeout);

      stopwatch.stop();

      if (response.statusCode == 200 && response.data != null) {
        final items = response.data['results'] as List? ?? response.data['data'] as List? ?? [];
        final candidates = <SearchCandidate>[];

        for (final item in items) {
          if (item is Map) {
            final ytId = item['youtubeId']?.toString() ?? item['id']?.toString() ?? '';
            final title = item['title']?.toString() ?? 'YouTube Track';
            final artist = item['artist']?.toString() ?? item['channelTitle']?.toString() ?? 'YouTube';
            final durationSec = (item['duration'] as num?)?.toInt() ?? 180;
            final thumbnail = item['artworkUrl']?.toString() ?? item['thumbnail']?.toString() ?? 'https://i.ytimg.com/vi/$ytId/hqdefault.jpg';
            final viewCount = (item['viewCount'] as num?)?.toInt();
            final likeCount = (item['likeCount'] as num?)?.toInt();
            final versionStr = item['versionType']?.toString();

            candidates.add(SearchCandidate(
              canonicalId: 'yt_$ytId',
              youtubeId: ytId,
              title: title,
              artist: artist,
              album: item['album']?.toString() ?? 'YouTube Music',
              channelOrOwner: item['channelTitle']?.toString() ?? artist,
              normalizedTitle: title.toLowerCase().trim(),
              normalizedArtist: artist.toLowerCase().trim(),
              duration: Duration(seconds: durationSec),
              versionType: versionStr != null ? TrackVersionType.fromString(versionStr) : _inferVersionType(title),
              sourceProvider: SearchProviderType.youtube,
              viewCount: viewCount,
              likeCount: likeCount,
              popularityScore: viewCount != null ? _calcViewPopularity(viewCount) : 0.6,
              publishedAt: item['publishedAt'] != null ? DateTime.tryParse(item['publishedAt'].toString()) : null,
              artworkUrl: thumbnail,
              playableUrl: item['streamUrl']?.toString(),
              previewUrl: item['streamUrl']?.toString(),
              isDownloadable: true,
              audioFormat: item['format']?.toString() ?? 'm4a',
              bitrate: item['bitrate']?.toString() ?? '320 kbps',
              providerMetadata: {
                'provider': 'youtube',
                'id': ytId,
                'channel': item['channelTitle'],
                'youtube_url': 'https://www.youtube.com/watch?v=$ytId',
              },
              matchedProviders: [SearchProviderType.youtube],
            ));
          }
        }

        health.recordSuccess(stopwatch.elapsed);
        return candidates;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Backend YouTube search returned status ${response.statusCode}',
        );
      }
    } on DioException catch (dioErr) {
      stopwatch.stop();
      final isTimeout = dioErr.type == DioExceptionType.connectionTimeout ||
          dioErr.type == DioExceptionType.receiveTimeout;
      final is429 = dioErr.response?.statusCode == 429;
      health.recordFailure(
        error: dioErr.message ?? dioErr.toString(),
        isTimeout: isTimeout,
        isRateLimit: is429,
        isHttpError: !isTimeout && !is429,
      );
      debugPrint('[YouTubeSearchProvider] ⚠️ Dio error: ${dioErr.message}');
      return [];
    } catch (e) {
      stopwatch.stop();
      health.recordFailure(error: e.toString());
      debugPrint('[YouTubeSearchProvider] ⚠️ Backend search error: $e');
      return [];
    }
  }

  double _calcViewPopularity(int views) {
    if (views <= 0) return 0.1;
    if (views < 100000) return 0.3;
    if (views < 1000000) return 0.6;
    if (views < 10000000) return 0.8;
    return 0.95;
  }

  TrackVersionType _inferVersionType(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('remix')) return TrackVersionType.remix;
    if (lower.contains('live')) return TrackVersionType.live;
    if (lower.contains('acoustic')) return TrackVersionType.acoustic;
    if (lower.contains('cover')) return TrackVersionType.cover;
    if (lower.contains('slowed') || lower.contains('reverb')) return TrackVersionType.slowed;
    if (lower.contains('lofi') || lower.contains('lo-fi')) return TrackVersionType.lofi;
    if (lower.contains('short') || lower.contains('#shorts')) return TrackVersionType.short;
    if (lower.contains('reaction')) return TrackVersionType.reaction;
    if (lower.contains('podcast')) return TrackVersionType.podcast;
    if (lower.contains('compilation') || lower.contains('jukebox')) return TrackVersionType.compilation;
    return TrackVersionType.official;
  }
}
