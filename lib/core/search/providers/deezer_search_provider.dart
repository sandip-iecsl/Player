import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/search_models.dart';
import 'provider_health.dart';
import 'search_provider.dart';

/// Provider 5: Deezer Preview & Metadata Search Provider
/// Feature flagged preview provider (30s high quality preview + rich metadata)
class DeezerSearchProvider implements SearchProviderClient {
  @override
  final SearchProviderType provider = SearchProviderType.deezer;

  @override
  final ProviderHealth health = ProviderHealth(provider: SearchProviderType.deezer);

  @override
  bool get isEnabled => dotenv.env['DEEZER_ENABLED']?.toLowerCase() != 'false';

  @override
  int get priority => 5;

  @override
  Duration get timeout => const Duration(seconds: 4);

  final Dio _dio;

  DeezerSearchProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.deezer.com',
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 4),
              headers: {
                'User-Agent': 'AuraPlayer/2.0 (Mobile; Android/iOS)',
                'Accept': 'application/json',
              },
            ));

  @override
  Future<List<SearchCandidate>> search(
    ParsedQuery query,
    SearchRequest request,
  ) async {
    if (!isEnabled) return [];
    if (!health.isAvailable) {
      debugPrint('[DeezerSearchProvider] ⚡ Circuit OPEN. Skipping request.');
      return [];
    }

    final stopwatch = Stopwatch()..start();
    try {
      final q = query.effectiveQuery;
      final response = await _dio.get(
        '/search',
        queryParameters: {
          'q': q,
          'limit': request.limit,
        },
      ).timeout(timeout);

      stopwatch.stop();

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is Map ? response.data['data'] as List? ?? [] : [];
        final candidates = <SearchCandidate>[];

        for (final item in data) {
          if (item is Map) {
            final id = item['id']?.toString() ?? '';
            final title = item['title']?.toString() ?? 'Unknown Title';
            final artistMap = item['artist'] as Map? ?? {};
            final artist = artistMap['name']?.toString() ?? 'Deezer Artist';
            final albumMap = item['album'] as Map? ?? {};
            final album = albumMap['title']?.toString() ?? 'Deezer Album';
            final durationSec = (item['duration'] as num?)?.toInt() ?? 180;
            final preview = item['preview']?.toString();
            final artwork = albumMap['cover_medium']?.toString() ??
                artistMap['picture_medium']?.toString();
            final rank = (item['rank'] as num?)?.toInt() ?? 0;

            candidates.add(SearchCandidate(
              canonicalId: 'deezer_$id',
              deezerId: id,
              isrc: item['isrc']?.toString(),
              title: title,
              artist: artist,
              album: album,
              channelOrOwner: artist,
              normalizedTitle: title.toLowerCase().trim(),
              normalizedArtist: artist.toLowerCase().trim(),
              normalizedAlbum: album.toLowerCase().trim(),
              duration: Duration(seconds: durationSec),
              versionType: _inferVersionType(title),
              sourceProvider: SearchProviderType.deezer,
              popularityScore: rank > 0 ? (rank / 1000000.0).clamp(0.0, 1.0) : 0.4,
              artworkUrl: artwork,
              playableUrl: preview,
              previewUrl: preview,
              isDownloadable: false, // 30s preview only
              audioFormat: 'mp3',
              bitrate: '128 kbps',
              providerMetadata: {
                'provider': 'deezer',
                'id': id,
                'link': item['link'],
                'explicit_lyrics': item['explicit_lyrics'],
              },
              matchedProviders: const [SearchProviderType.deezer],
            ));
          }
        }

        health.recordSuccess(stopwatch.elapsed);
        return candidates;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Deezer returned ${response.statusCode}',
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
      debugPrint('[DeezerSearchProvider] ⚠️ Dio error: ${dioErr.message}');
      return [];
    } catch (e) {
      stopwatch.stop();
      health.recordFailure(error: e.toString());
      debugPrint('[DeezerSearchProvider] ⚠️ General error: $e');
      return [];
    }
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
