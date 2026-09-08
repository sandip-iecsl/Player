import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../data/models/song_model.dart';
import '../search_engine_provider.dart';
import '../search_tier.dart';

/// Tier 1: Primary Cloud Search Provider
/// 
/// Powered by MongoDB Atlas Search (Apache Lucene built into free M0 cluster).
/// Supports Lucene autocomplete, fuzzy text matching (`maxEdits: 2`), and relevance scoring.
class MongoAtlasSearchProvider implements ISearchEngineProvider {
  @override
  String get providerName => 'MongoDB Atlas Search (Primary M0)';

  @override
  SearchTier get tier => SearchTier.tier1MongoAtlas;

  final Dio _dio;
  final String? _customEndpoint;
  final String? _apiKey;
  final String _database;
  final String _collection;
  final String _indexName;

  MongoAtlasSearchProvider({
    Dio? dio,
    String? customEndpoint,
    String? apiKey,
    String database = 'aura_music',
    String collection = 'songs',
    String indexName = 'search_index',
  })  : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 3),
              headers: {'Content-Type': 'application/json'},
            )),
        _customEndpoint = customEndpoint,
        _apiKey = apiKey,
        _database = database,
        _collection = collection,
        _indexName = indexName;

  @override
  Future<List<SongModel>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // If a custom Atlas Data API / App Services HTTPS endpoint is provided
    final endpoint = _customEndpoint;
    if (endpoint != null && endpoint.isNotEmpty) {
      try {
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
                        'path': ['album', 'language'],
                        'fuzzy': {'maxEdits': 1}
                      }
                    }
                  ]
                }
              }
            },
            {r'$limit': 30}
          ]
        };

        final headers = <String, dynamic>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        };
        if (_apiKey != null && _apiKey!.isNotEmpty) {
          headers['api-key'] = _apiKey!;
        }

        final response = await _dio.post(
          endpoint,
          data: jsonEncode(payload),
          options: Options(headers: headers),
        );

        if (response.statusCode == 200) {
          final data = response.data;
          List<dynamic> documents = [];
          if (data is Map && data.containsKey('documents')) {
            documents = data['documents'] as List;
          } else if (data is List) {
            documents = data;
          }

          final results = <SongModel>[];
          for (final doc in documents) {
            if (doc is Map<String, dynamic>) {
              try {
                results.add(SongModel.fromJson(doc));
              } catch (e) {
                debugPrint('[$providerName] Error parsing song document: $e');
              }
            }
          }
          return results;
        } else if (response.statusCode == 429) {
          throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
            error: 'Atlas Rate Limit Exceeded (429)',
          );
        } else {
          throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
            error: 'Atlas Server Error: ${response.statusCode}',
          );
        }
      } on DioException catch (dioErr) {
        debugPrint('[$providerName] DioException in Atlas Search: ${dioErr.message}');
        rethrow;
      } catch (e) {
        debugPrint('[$providerName] General Exception in Atlas Search: $e');
        rethrow;
      }
    }

    // Default primary cloud fallback endpoint / simulation check
    // In production without custom endpoint configured, throw to trigger instant failover to Tier 2
    throw DioException(
      requestOptions: RequestOptions(path: 'mongodb_atlas_m0'),
      type: DioExceptionType.connectionError,
      error: 'MongoDB Atlas Search endpoint unconfigured or unreachable. Triggering failover.',
    );
  }

  @override
  Future<bool> isHealthy() async {
    return _customEndpoint != null && _customEndpoint!.isNotEmpty;
  }
}
