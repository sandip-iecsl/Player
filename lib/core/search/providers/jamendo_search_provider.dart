import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/search_models.dart';
import 'provider_health.dart';
import 'search_provider.dart';

/// Provider 3: Jamendo Open Music API
/// Free CC music search and stream/download with explicit licensing check
class JamendoSearchProvider implements SearchProviderClient {
  @override
  final SearchProviderType provider = SearchProviderType.jamendo;

  @override
  final ProviderHealth health = ProviderHealth(provider: SearchProviderType.jamendo);

  @override
  bool get isEnabled => true;

  @override
  int get priority => 3;

  @override
  Duration get timeout => const Duration(seconds: 4);

  final Dio _dio;
  static const String _defaultClientId = '56d30c95'; // Jamendo Public App ID

  JamendoSearchProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.jamendo.com/v3.0',
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 4),
              headers: {
                'User-Agent': 'AuraPlayer/2.0 (Mobile; Android/iOS; https://auraplayer.app)',
                'Accept': 'application/json',
              },
            ));

  String get _clientId => dotenv.env['JAMENDO_CLIENT_ID']?.trim().isNotEmpty == true
      ? dotenv.env['JAMENDO_CLIENT_ID']!.trim()
      : _defaultClientId;

  @override
  Future<List<SearchCandidate>> search(
    ParsedQuery query,
    SearchRequest request,
  ) async {
    if (!health.isAvailable) {
      debugPrint('[JamendoSearchProvider] ⚡ Circuit OPEN. Skipping request.');
      return [];
    }

    final stopwatch = Stopwatch()..start();
    try {
      final q = query.effectiveQuery;
      final response = await _dio.get(
        '/tracks/',
        queryParameters: {
          'client_id': _clientId,
          'format': 'json',
          'limit': request.limit,
          'namesearch': q,
          'include': 'musicinfo+licenses',
          'audioformat': 'mp32',
        },
      ).timeout(timeout);

      stopwatch.stop();

      if (response.statusCode == 200 && response.data != null) {
        final results = response.data['results'] as List? ?? [];
        final candidates = <SearchCandidate>[];

        for (final item in results) {
          if (item is Map) {
            final trackId = item['id']?.toString() ?? '';
            final title = item['name']?.toString() ?? 'Unknown Title';
            final artist = item['artist_name']?.toString() ?? 'Jamendo Artist';
            final album = item['album_name']?.toString() ?? 'Jamendo Album';
            final durationSec = (item['duration'] as num?)?.toInt() ?? 180;
            final image = item['image']?.toString() ?? item['album_image']?.toString();
            final audioStream = item['audio']?.toString();
            final audioDownload = item['audiodownload']?.toString();
            final downloadAllowed = item['audiodownload_allowed'] == true;
            final license = item['license_ccurl']?.toString();

            candidates.add(SearchCandidate(
              canonicalId: 'jamendo_$trackId',
              jamendoId: trackId,
              title: title,
              artist: artist,
              album: album,
              channelOrOwner: artist,
              normalizedTitle: title.toLowerCase().trim(),
              normalizedArtist: artist.toLowerCase().trim(),
              normalizedAlbum: album.toLowerCase().trim(),
              duration: Duration(seconds: durationSec),
              versionType: _inferVersionType(title),
              sourceProvider: SearchProviderType.jamendo,
              artworkUrl: image,
              playableUrl: audioStream,
              previewUrl: audioStream,
              isDownloadable: downloadAllowed && audioDownload != null,
              audioFormat: 'mp3',
              bitrate: '192 kbps',
              providerMetadata: {
                'provider': 'jamendo',
                'audiodownload_allowed': downloadAllowed,
                'download_url': downloadAllowed ? audioDownload : null,
                'license': license,
                'share_url': item['shareurl'],
              },
              matchedProviders: const [SearchProviderType.jamendo],
            ));
          }
        }

        health.recordSuccess(stopwatch.elapsed);
        return candidates;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Jamendo API error: ${response.statusCode}',
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
      debugPrint('[JamendoSearchProvider] ⚠️ Dio error: ${dioErr.message}');
      return [];
    } catch (e) {
      stopwatch.stop();
      health.recordFailure(error: e.toString());
      debugPrint('[JamendoSearchProvider] ⚠️ General error: $e');
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
