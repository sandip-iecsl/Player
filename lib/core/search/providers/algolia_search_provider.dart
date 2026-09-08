import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../data/models/song_model.dart';
import '../search_engine_provider.dart';
import '../search_tier.dart';

/// Tier 2: Secondary Cloud Backup Search Provider
/// 
/// Powered by Algolia Free Tier (10,000 free search operations/month).
/// Acts as the high-speed cloud backup if Tier 1 experiences latency spikes, 429 limits, or downtime.
class AlgoliaSearchProvider implements ISearchEngineProvider {
  @override
  String get providerName => 'Algolia Search (Secondary Tier 2)';

  @override
  SearchTier get tier => SearchTier.tier2Algolia;

  final Dio _dio;
  final String? _appId;
  final String? _apiKey;
  final String _indexName;

  AlgoliaSearchProvider({
    Dio? dio,
    String? appId,
    String? apiKey,
    String indexName = 'songs_index',
  })  : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 3),
              headers: {'Content-Type': 'application/json'},
            )),
        _appId = appId,
        _apiKey = apiKey,
        _indexName = indexName;

  @override
  Future<List<SongModel>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final appId = _appId;
    final apiKey = _apiKey;

    if (appId != null && appId.isNotEmpty && apiKey != null && apiKey.isNotEmpty) {
      try {
        final url = 'https://$appId-dsn.algolia.net/1/indexes/$_indexName/query';
        final response = await _dio.post(
          url,
          data: {
            'query': cleanQuery,
            'hitsPerPage': 30,
            'attributesToRetrieve': [
              'id',
              'objectID',
              'title',
              'artist',
              'albumArt',
              'album',
              'duration',
              'durationMs',
              'youtubeUrl',
              'deezerUrl',
              'previewUrl',
              'language',
              'isYoutubeImport'
            ],
          },
          options: Options(
            headers: {
              'X-Algolia-Application-Id': appId,
              'X-Algolia-API-Key': apiKey,
            },
          ),
        );

        if (response.statusCode == 200) {
          final data = response.data;
          if (data is Map && data.containsKey('hits')) {
            final hits = data['hits'] as List;
            final results = <SongModel>[];
            for (final hit in hits) {
              if (hit is Map<String, dynamic>) {
                try {
                  // Normalize objectID if id is absent
                  final mappedDoc = Map<String, dynamic>.from(hit);
                  if (!mappedDoc.containsKey('id') && mappedDoc.containsKey('objectID')) {
                    mappedDoc['id'] = mappedDoc['objectID'];
                  }
                  results.add(SongModel.fromJson(mappedDoc));
                } catch (e) {
                  debugPrint('[$providerName] Error parsing Algolia hit: $e');
                }
              }
            }
            return results;
          }
          return [];
        } else if (response.statusCode == 429 || response.statusCode == 402 || response.statusCode == 403) {
          throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
            error: 'Algolia Quota/Rate Limit Exceeded (${response.statusCode})',
          );
        } else {
          throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
            error: 'Algolia Server Error: ${response.statusCode}',
          );
        }
      } on DioException catch (dioErr) {
        debugPrint('[$providerName] DioException in Algolia Search: ${dioErr.message}');
        rethrow;
      } catch (e) {
        debugPrint('[$providerName] Exception in Algolia Search: $e');
        rethrow;
      }
    }

    // If unconfigured or missing credentials, trigger failover to Tier 3
    throw DioException(
      requestOptions: RequestOptions(path: 'algolia_free_tier'),
      type: DioExceptionType.connectionError,
      error: 'Algolia credentials unconfigured or service unavailable. Triggering failover.',
    );
  }

  @override
  Future<bool> isHealthy() async {
    return _appId != null && _appId!.isNotEmpty && _apiKey != null && _apiKey!.isNotEmpty;
  }
}
