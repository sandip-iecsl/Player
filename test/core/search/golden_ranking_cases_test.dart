import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_player/core/search/models/search_models.dart';
import 'package:aura_player/core/search/query/query_intelligence.dart';
import 'package:aura_player/core/search/ranking/aura_search_ranker.dart';

void main() {
  group('Golden 100+ Search Ranking & Intent Verification Suite', () {
    late List<dynamic> fixtureCases;
    final intelligence = QueryIntelligence();
    final ranker = AuraSearchRanker();

    setUpAll(() {
      final file = File('test/fixtures/search_ranking_cases.json');
      final jsonString = file.readAsStringSync();
      fixtureCases = jsonDecode(jsonString) as List<dynamic>;
    });

    test('Loads at least 100 realistic search fixtures', () {
      expect(fixtureCases.length, greaterThanOrEqualTo(100));
    });

    test('Validates query intelligence & intent across all 100+ fixtures', () {
      for (final rawCase in fixtureCases) {
        final fixture = rawCase as Map<String, dynamic>;
        final queryStr = fixture['query']?.toString() ?? '';
        final expectedIntentStr = fixture['expectedIntent']?.toString();

        final parsed = intelligence.parse(queryStr);

        if (expectedIntentStr != null && expectedIntentStr.isNotEmpty) {
          final expectedIntent = QueryIntent.fromString(expectedIntentStr);
          expect(
            parsed.intent,
            equals(expectedIntent),
            reason: 'Failed intent detection on query: "$queryStr" (Case ID: ${fixture['id']})',
          );
        }
      }
    });

    test('Evaluates candidate ranking stability for representative test cases', () {
      final representativeQueries = [
        'arjit tum hi ho',
        'shreya ghosl',
        'tum hi ho live concert',
        'tum hi ho slowed reverb',
        'kesariya arijit',
        'starboy the weeknd',
        'perfect ed sheeran',
      ];

      for (final queryStr in representativeQueries) {
        final parsed = intelligence.parse(queryStr);

        final candidates = [
          SearchCandidate(
            canonicalId: 'candidate_exact',
            title: parsed.entities.title ?? parsed.effectiveQuery,
            artist: parsed.entities.artist ?? 'Arijit Singh',
            normalizedTitle: (parsed.entities.title ?? parsed.effectiveQuery).toLowerCase(),
            normalizedArtist: (parsed.entities.artist ?? 'Arijit Singh').toLowerCase(),
            duration: const Duration(seconds: 240),
            versionType: parsed.entities.version ?? TrackVersionType.official,
            sourceProvider: SearchProviderType.jiosaavn,
            popularityScore: 0.7,
          ),
          SearchCandidate(
            canonicalId: 'candidate_reaction',
            title: '${parsed.effectiveQuery} Reaction Video',
            artist: 'Random Creator',
            normalizedTitle: '${parsed.effectiveQuery} reaction video'.toLowerCase(),
            normalizedArtist: 'random creator',
            duration: const Duration(seconds: 700),
            versionType: TrackVersionType.reaction,
            sourceProvider: SearchProviderType.youtube,
            popularityScore: 0.9,
          ),
          const SearchCandidate(
            canonicalId: 'candidate_unrelated',
            title: 'Unrelated Top Hit 2024',
            artist: 'Another Artist',
            normalizedTitle: 'unrelated top hit 2024',
            normalizedArtist: 'another artist',
            duration: Duration(seconds: 210),
            sourceProvider: SearchProviderType.spotify,
            popularityScore: 0.95,
          ),
        ];

        final ranked = ranker.rank(candidates: candidates, query: parsed);

        expect(ranked.first.candidate.canonicalId, equals('candidate_exact'),
            reason: 'Exact candidate did not rank #1 for query: "$queryStr"');
        expect(ranked.last.candidate.canonicalId, isNot(equals('candidate_exact')),
            reason: 'Exact candidate ranked last for query: "$queryStr"');
      }
    });
  });
}
