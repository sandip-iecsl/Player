import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/search_models.dart';
import 'provider_health.dart';
import 'search_provider.dart';

/// Provider 2: Audius Decentralized Music API
/// Free search and streaming tier with host discovery
class AudiusSearchProvider implements SearchProviderClient {
  @override
  final SearchProviderType provider = SearchProviderType.audius;

  @override
  final ProviderHealth health = ProviderHealth(provider: SearchProviderType.audius);

  @override
  bool get isEnabled => true;

  @override
  int get priority => 2;

  @override
  Duration get timeout => const Duration(seconds: 4);

  final Dio _dio;
  String _host = 'https://discoveryprovider.audius.co';
  static const String _appName = 'AURA_PLAYER';

  AudiusSearchProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 4),
              headers: {
                'User-Agent': 'AuraPlayer/2.0 (Mobile; Android/iOS; https://auraplayer.app)',
                'Accept': 'application/json',
              },
            ));

  Future<void> _discoverHost() async {
    try {
      final res = await _dio.get('https://api.audius.co', options: Options(responseType: ResponseType.json));
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data['data'];
        if (data is List && data.isNotEmpty) {
          _host = data.first.toString();
        }
      }
    } catch (_) {
      // Fallback host retained
    }
  }

  @override
  Future<List<SearchCandidate>> search(
    ParsedQuery query,
    SearchRequest request,
  ) async {
    if (!health.isAvailable) {
      debugPrint('[AudiusSearchProvider] ⚡ Circuit OPEN. Skipping request.');
      return [];
    }

    final stopwatch = Stopwatch()..start();
    try {
      final q = query.effectiveQuery;
      final uri = '$_host/v1/tracks/search';

      final response = await _dio.get(
        uri,
        queryParameters: {
          'query': q,
          'app_name': _appName,
        },
      ).timeout(timeout);

      stopwatch.stop();

      if (response.statusCode == 200 && response.data != null) {
        final list = response.data['data'] as List? ?? [];
        final candidates = <SearchCandidate>[];

        for (final item in list.take(request.limit)) {
          if (item is Map) {
            final trackId = item['id']?.toString() ?? '';
            final title = item['title']?.toString() ?? 'Unknown Track';
            final user = item['user'] as Map? ?? {};
            final artist = user['name']?.toString() ?? user['handle']?.toString() ?? 'Audius Artist';
            final durationSec = (item['duration'] as num?)?.toInt() ?? 180;
            final artwork = item['artwork']?['480x480']?.toString() ??
                item['artwork']?['150x150']?.toString();
            final playCount = (item['play_count'] as num?)?.toInt() ?? 0;
            final genre = item['genre']?.toString();

            final streamUrl = '$_host/v1/tracks/$trackId/stream?app_name=$_appName';

            candidates.add(SearchCandidate(
              canonicalId: 'audius_$trackId',
              audiusId: trackId,
              title: title,
              artist: artist,
              album: genre ?? 'Audius Release',
              channelOrOwner: user['handle']?.toString(),
              normalizedTitle: title.toLowerCase().trim(),
              normalizedArtist: artist.toLowerCase().trim(),
              normalizedAlbum: genre?.toLowerCase().trim(),
              duration: Duration(seconds: durationSec),
              versionType: _inferVersionType(title),
              sourceProvider: SearchProviderType.audius,
              viewCount: playCount,
              popularityScore: _calcPopularity(playCount),
              artworkUrl: artwork,
              playableUrl: streamUrl,
              previewUrl: streamUrl,
              isDownloadable: item['downloadable'] == true,
              audioFormat: 'mp3',
              bitrate: '320 kbps',
              providerMetadata: {
                'provider': 'audius',
                'genre': genre,
                'repost_count': item['repost_count'],
                'favorite_count': item['favorite_count'],
              },
              matchedProviders: const [SearchProviderType.audius],
            ));
          }
        }

        health.recordSuccess(stopwatch.elapsed);
        return candidates;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Audius API returned status ${response.statusCode}',
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
      debugPrint('[AudiusSearchProvider] ⚠️ Dio error: ${dioErr.message}');
      return [];
    } catch (e) {
      stopwatch.stop();
      health.recordFailure(error: e.toString());
      debugPrint('[AudiusSearchProvider] ⚠️ General error: $e');
      return [];
    }
  }

  double _calcPopularity(int plays) {
    if (plays <= 0) return 0.05;
    if (plays < 1000) return 0.2;
    if (plays < 10000) return 0.5;
    if (plays < 100000) return 0.75;
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
    return TrackVersionType.official;
  }
}
