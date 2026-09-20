import 'package:flutter_test/flutter_test.dart';
import 'package:aura_player/core/search/dedup/canonical_track_resolver.dart';
import 'package:aura_player/core/search/dedup/search_deduplicator.dart';
import 'package:aura_player/core/search/diversity/result_diversifier.dart';
import 'package:aura_player/core/search/models/search_models.dart';
import 'package:aura_player/core/search/query/query_intelligence.dart';

void main() {
  group('Deduplication & Diversification Suite', () {
    final intelligence = QueryIntelligence();

    test('Canonical resolver merges identical tracks across YouTube, JioSaavn, and Spotify', () {
      const ytCandidate = SearchCandidate(
        canonicalId: 'yt_123',
        youtubeId: '12345678901',
        title: 'Tum Hi Ho',
        artist: 'Arijit Singh',
        normalizedTitle: 'tum hi ho',
        normalizedArtist: 'arijit singh',
        duration: Duration(seconds: 262),
        sourceProvider: SearchProviderType.youtube,
      );

      const saavnCandidate = SearchCandidate(
        canonicalId: 'saavn_456',
        jioSaavnId: 'saavn_456',
        title: 'Tum Hi Ho',
        artist: 'Arijit Singh',
        normalizedTitle: 'tum hi ho',
        normalizedArtist: 'arijit singh',
        duration: Duration(seconds: 264),
        sourceProvider: SearchProviderType.jiosaavn,
        playableUrl: 'https://saavn.com/stream/456.mp3',
      );

      const spotifyCandidate = SearchCandidate(
        canonicalId: 'spotify_789',
        spotifyId: 'spotify_789',
        isrc: 'INUM71300001',
        title: 'Tum Hi Ho',
        artist: 'Arijit Singh',
        normalizedTitle: 'tum hi ho',
        normalizedArtist: 'arijit singh',
        duration: Duration(seconds: 262),
        sourceProvider: SearchProviderType.spotify,
      );

      expect(CanonicalTrackResolver.areSameTrack(ytCandidate, saavnCandidate), isTrue);
      expect(CanonicalTrackResolver.areSameTrack(saavnCandidate, spotifyCandidate), isTrue);

      final deduped = SearchDeduplicator.deduplicate([ytCandidate, saavnCandidate, spotifyCandidate]);

      expect(deduped.length, equals(1));
      final merged = deduped.first;
      expect(merged.youtubeId, equals('12345678901'));
      expect(merged.jioSaavnId, equals('saavn_456'));
      expect(merged.spotifyId, equals('spotify_789'));
      expect(merged.isrc, equals('INUM71300001'));
      expect(merged.playableUrl, isNotNull);
    });

    test('Canonical resolver does NOT merge different songs with identical titles by different artists', () {
      const edSheeran = SearchCandidate(
        canonicalId: 'ed_1',
        title: 'Perfect',
        artist: 'Ed Sheeran',
        normalizedTitle: 'perfect',
        normalizedArtist: 'ed sheeran',
        duration: Duration(seconds: 263),
        sourceProvider: SearchProviderType.spotify,
      );

      const simplePlan = SearchCandidate(
        canonicalId: 'sp_1',
        title: 'Perfect',
        artist: 'Simple Plan',
        normalizedTitle: 'perfect',
        normalizedArtist: 'simple plan',
        duration: Duration(seconds: 278),
        sourceProvider: SearchProviderType.spotify,
      );

      expect(CanonicalTrackResolver.areSameTrack(edSheeran, simplePlan), isFalse);

      final deduped = SearchDeduplicator.deduplicate([edSheeran, simplePlan]);
      expect(deduped.length, equals(2));
    });

    test('Result Diversifier limits artist clustering while preserving top match at #1', () {
      final query = intelligence.parse('romantic songs');
      const diversifier = ResultDiversifier(maxPerArtist: 2, maxPerVersion: 2);

      final ranked = List.generate(8, (i) {
        return RankedCandidate(
          candidate: SearchCandidate(
            canonicalId: 'song_$i',
            title: 'Song $i',
            artist: 'Arijit Singh',
            normalizedTitle: 'song $i',
            normalizedArtist: 'arijit singh',
            duration: const Duration(seconds: 200),
            sourceProvider: SearchProviderType.jiosaavn,
          ),
          finalScore: 0.90 - (i * 0.05),
          features: const RankingFeatures(),
        );
      });

      final diversified = diversifier.diversify(rankedResults: ranked, query: query);

      // Must keep all songs, but top prioritized group should adhere to limits
      expect(diversified.first.candidate.canonicalId, equals('song_0'));
      expect(diversified.length, equals(8));
    });
  });
}
