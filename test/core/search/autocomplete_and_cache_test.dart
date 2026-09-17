import 'package:flutter_test/flutter_test.dart';
import 'package:aura_player/core/search/autocomplete/autocomplete_engine.dart';
import 'package:aura_player/core/search/autocomplete/autocomplete_index.dart';
import 'package:aura_player/core/search/autocomplete/did_you_mean_engine.dart';
import 'package:aura_player/core/search/cache/search_cache_key.dart';
import 'package:aura_player/core/search/models/search_models.dart';
import 'package:aura_player/core/search/query/query_intelligence.dart';

void main() {
  group('Autocomplete, Did-You-Mean & Cache Suite', () {
    final intelligence = QueryIntelligence();

    test('AutocompleteIndex Trie inserts and queries prefix suggestions rapidly', () {
      final index = AutocompleteIndex();
      index.insertAll(['arijit singh', 'arijit singh songs', 'apna bana le', 'kesariya']);

      final results = index.lookupPrefix('ari');
      expect(results.contains('arijit singh'), isTrue);
      expect(results.contains('arijit singh songs'), isTrue);
      expect(results.contains('kesariya'), isFalse);
    });

    test('AutocompleteEngine returns real-time suggestions', () {
      final engine = AutocompleteEngine();
      final suggestions = engine.getSuggestions('tum');

      expect(suggestions.isNotEmpty, isTrue);
      expect(suggestions.any((s) => s.contains('tum hi ho')), isTrue);
    });

    test('DidYouMeanEngine produces typo corrections and suppresses on exact match', () {
      final typoQuery = intelligence.parse('arjit singh');
      final suggestion = DidYouMeanEngine.evaluate(
        query: typoQuery,
        topResults: [],
      );

      expect(suggestion, equals('Arijit Singh'));

      final exactQuery = intelligence.parse('arijit singh');
      final suppressedSuggestion = DidYouMeanEngine.evaluate(
        query: exactQuery,
        topResults: const [
          RankedCandidate(
            candidate: SearchCandidate(
              canonicalId: '1',
              title: 'Channa Mereya',
              artist: 'Arijit Singh',
              normalizedTitle: 'channa mereya',
              normalizedArtist: 'arijit singh',
              duration: Duration(seconds: 289),
              sourceProvider: SearchProviderType.local,
            ),
            finalScore: 0.88,
            features: RankingFeatures(),
          )
        ],
      );

      expect(suppressedSuggestion, isNull);
    });

    test('SearchCacheKey serializes structured key properly', () {
      final query = intelligence.parse('tum hi ho');
      final key = SearchCacheKey.fromParsedQuery(query, region: 'IN');

      expect(key.serialize(), equals('tum hi ho|song|hi|IN'));
    });
  });
}
