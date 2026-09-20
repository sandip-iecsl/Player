import 'package:flutter_test/flutter_test.dart';
import 'package:aura_player/core/search/models/search_models.dart';
import 'package:aura_player/core/search/query/query_intelligence.dart';
import 'package:aura_player/core/search/ranking/aura_search_ranker.dart';
import 'package:aura_player/core/search/ranking/score_boosts.dart';
import 'package:aura_player/core/search/ranking/score_penalties.dart';
import 'package:aura_player/core/search/ranking/string_similarity.dart';

void main() {
  group('Ranking Pipeline & Scoring Suite', () {
    final intelligence = QueryIntelligence();
    final ranker = AuraSearchRanker();

    test('String similarity computes Levenshtein, Jaro-Winkler, and N-gram metrics', () {
      expect(StringSimilarity.levenshteinSimilarity('arijit', 'arijit'), equals(1.0));
      expect(StringSimilarity.levenshteinSimilarity('arjit', 'arijit'), greaterThan(0.7));
      expect(StringSimilarity.jaroWinkler('tum hi ho', 'tum hi ho'), equals(1.0));
      expect(StringSimilarity.nGramSimilarity('kesariya', 'kesariya'), equals(1.0));
      expect(StringSimilarity.tokenOverlapScore('arijit singh tum hi ho', 'tum hi ho arijit singh'), equals(1.0));
    });

    test('Exact match boosting prioritizes exact song title over popular compilations', () {
      final query = intelligence.parse('tum hi ho');

      const officialSong = SearchCandidate(
        canonicalId: '1',
        title: 'Tum Hi Ho',
        artist: 'Arijit Singh',
        normalizedTitle: 'tum hi ho',
        normalizedArtist: 'arijit singh',
        duration: Duration(seconds: 262),
        versionType: TrackVersionType.official,
        sourceProvider: SearchProviderType.jiosaavn,
        viewCount: 500000,
        popularityScore: 0.6,
      );

      const popularCompilation = SearchCandidate(
        canonicalId: '2',
        title: 'Top Bollywood Romantic Songs Jukebox',
        artist: 'Various Artists',
        normalizedTitle: 'top bollywood romantic songs jukebox',
        normalizedArtist: 'various artists',
        duration: Duration(seconds: 3600),
        versionType: TrackVersionType.compilation,
        sourceProvider: SearchProviderType.youtube,
        viewCount: 50000000,
        popularityScore: 0.99,
      );

      const reactionVideo = SearchCandidate(
        canonicalId: '3',
        title: 'Tum Hi Ho - American Reacts to Arijit Singh',
        artist: 'YouTuber Reactor',
        normalizedTitle: 'tum hi ho american reacts to arijit singh',
        normalizedArtist: 'youtuber reactor',
        duration: Duration(seconds: 600),
        versionType: TrackVersionType.reaction,
        sourceProvider: SearchProviderType.youtube,
        viewCount: 2000000,
        popularityScore: 0.8,
      );

      final ranked = ranker.rank(
        candidates: [popularCompilation, reactionVideo, officialSong],
        query: query,
      );

      // Official Tum Hi Ho MUST rank #1 despite lower raw global viewcount
      expect(ranked.first.candidate.canonicalId, equals('1'));
      expect(ranked.first.candidate.title, equals('Tum Hi Ho'));
      expect(ranked.first.finalScore, greaterThan(ranked[1].finalScore));
      expect(ranked.first.finalScore, greaterThan(ranked[2].finalScore));
    });

    test('Score Boosts and Penalties remain within valid bounded range [0.0 - 1.0]', () {
      final query = intelligence.parse('tum hi ho live');

      const liveCandidate = SearchCandidate(
        canonicalId: '1',
        title: 'Tum Hi Ho Live',
        artist: 'Arijit Singh',
        normalizedTitle: 'tum hi ho live',
        normalizedArtist: 'arijit singh',
        duration: Duration(seconds: 300),
        versionType: TrackVersionType.live,
        sourceProvider: SearchProviderType.youtube,
      );

      final boost = ScoreBoosts.calculateBoost(liveCandidate, query);
      final penalty = ScorePenalties.calculatePenalty(liveCandidate, query);

      expect(boost, greaterThan(0.0));
      expect(penalty, equals(0.0));

      final ranked = ranker.rank(candidates: [liveCandidate], query: query);
      expect(ranked.first.finalScore, lessThanOrEqualTo(1.0));
      expect(ranked.first.finalScore, greaterThan(0.0));
    });
  });
}
