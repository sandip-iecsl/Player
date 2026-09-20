import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/search_models.dart';
import 'provider_health.dart';
import 'search_provider.dart';

/// Provider 8: MongoDB Atlas Search Provider
/// Queries custom indexed song metadata on Atlas M0 cluster via Data API / App Services
class MongoDBSearchProvider implements SearchProviderClient {
  @override
  final SearchProviderType provider = SearchProviderType.mongodb;

  @override
  final ProviderHealth health = ProviderHealth(provider: SearchProviderType.mongodb);

  @override
  bool get isEnabled => dotenv.env['MONGODB_URI']?.isNotEmpty == true ||
      dotenv.env['MONGODB_DATA_API_URL']?.isNotEmpty == true;

  @override
  int get priority => 8;

  @override
  Duration get timeout => const Duration(seconds: 4);

  final Dio _dio;

  MongoDBSearchProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 4),
              headers: {'Content-Type': 'application/json'},
            ));

  String get _endpoint => dotenv.env['MONGODB_DATA_API_URL']?.trim() ?? '';
  String get _apiKey => dotenv.env['MONGODB_API_KEY']?.trim() ?? '';
  String get _database => dotenv.env['MONGODB_DATABASE']?.trim() ?? 'aura_player';
  String get _collection => dotenv.env['MONGODB_COLLECTION']?.trim() ?? 'songs';
  String get _indexName => dotenv.env['MONGODB_SEARCH_INDEX']?.trim() ?? 'search_index';

  @override
  Future<List<SearchCandidate>> search(
    ParsedQuery query,
    SearchRequest request,
  ) async {
    if (!isEnabled || _endpoint.isEmpty) return [];
    if (!health.isAvailable) {
      debugPrint('[MongoDBSearchProvider] ⚡ Circuit OPEN. Skipping request.');
      return [];
    }

    final stopwatch = Stopwatch()..start();
    try {
      final cleanQuery = query.effectiveQuery;
      final payload = {
        'collection': _collection,
        'database': _database,
        'dataSource': 'Cluster0',
        'pipeline': [
          {
            r'$search': {
              'index': _indexName,
              'compound': {
                'should': [
                  {
                    'autocomplete': {
                      'query': cleanQuery,
                      'path': 'title',
                      'fuzzy': {'maxEdits': 2, 'prefixLength': 1},
                      'score': {'boost': {'value': 3}}
                    }
                  },
                  {
                    'autocomplete': {
                      'query': cleanQuery,
                      'path': 'artist',
                      'fuzzy': {'maxEdits': 2, 'prefixLength': 1},
                      'score': {'boost': {'value': 2}}
                    }
                  },
                  {
                    'text': {
                      'query': cleanQuery,
                      'path': 'album',
                      'fuzzy': {'maxEdits': 1}
                    }
                  }
                ]
              }
            }
          },
          {r'$limit': request.limit}
        ]
      };

      final response = await _dio.post(
        _endpoint,
        data: payload,
        options: Options(headers: {
          if (_apiKey.isNotEmpty) 'api-key': _apiKey,
        }),
      ).timeout(timeout);

      stopwatch.stop();

      if (response.statusCode == 200 && response.data != null) {
        final docs = response.data['documents'] as List? ?? [];
        final candidates = <SearchCandidate>[];

        for (final doc in docs) {
          if (doc is Map) {
            final id = doc['_id']?.toString() ?? doc['id']?.toString() ?? '';
            final title = doc['title']?.toString() ?? 'Unknown Title';
            final artist = doc['artist']?.toString() ?? 'Unknown Artist';
            final album = doc['album']?.toString();
            final durationSec = (doc['duration'] as num?)?.toInt() ?? 180;
            final artwork = doc['albumArt']?.toString() ?? doc['thumbnailUrl']?.toString();
            final ytUrl = doc['youtubeUrl']?.toString();
            final deezerUrl = doc['deezerUrl']?.toString();
            final previewUrl = doc['previewUrl']?.toString();
            final viewCount = (doc['viewCount'] as num?)?.toInt();

            candidates.add(SearchCandidate(
              canonicalId: 'mongo_$id',
              youtubeId: ytUrl != null ? SearchCandidate.extractYtId(ytUrl) : null,
              deezerId: deezerUrl,
              title: title,
              artist: artist,
              album: album,
              normalizedTitle: title.toLowerCase().trim(),
              normalizedArtist: artist.toLowerCase().trim(),
              normalizedAlbum: album?.toLowerCase().trim(),
              duration: Duration(seconds: durationSec),
              versionType: _inferVersionType(title),
              sourceProvider: SearchProviderType.mongodb,
              viewCount: viewCount,
              popularityScore: doc['popularity'] is num ? (doc['popularity'] as num).toDouble() : 0.5,
              artworkUrl: artwork,
              playableUrl: previewUrl ?? ytUrl,
              previewUrl: previewUrl,
              isDownloadable: true,
              matchedProviders: const [SearchProviderType.mongodb],
            ));
          }
        }

        health.recordSuccess(stopwatch.elapsed);
        return candidates;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'MongoDB Atlas Search API error: ${response.statusCode}',
        );
      }
    } catch (e) {
      stopwatch.stop();
      final isTimeout = e.toString().contains('TimeoutException');
      final is429 = e.toString().contains('429');
      health.recordFailure(
        error: e.toString(),
        isTimeout: isTimeout,
        isRateLimit: is429,
        isHttpError: !isTimeout && !is429,
      );
      debugPrint('[MongoDBSearchProvider] ⚠️ Error querying MongoDB Atlas: $e');
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
