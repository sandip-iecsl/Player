import 'package:flutter_test/flutter_test.dart';
import 'package:aura_player/core/search/normalization/ngram_tokenizer.dart';
import 'package:aura_player/core/search/ranking/string_similarity.dart';
import 'package:aura_player/core/search/ranking/youtube_relevance_ranker.dart';
import 'package:aura_player/data/models/song_model.dart';
import 'package:aura_player/data/models/youtube_audio_format.dart';

void main() {
  group('YouTube-Style Search & Multi-Format Extraction Suite', () {
    test('NGramTokenizer normalizes text and generates prefix edge-grams', () {
      final tokens = NGramTokenizer.generateSearchTokens(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
      );

      expect(tokens.contains('bl'), isTrue);
      expect(tokens.contains('bli'), isTrue);
      expect(tokens.contains('blin'), isTrue);
      expect(tokens.contains('blind'), isTrue);
      expect(tokens.contains('blinding'), isTrue);
      expect(tokens.contains('lights'), isTrue);
      expect(tokens.contains('weeknd'), isTrue);
    });

    test('StringSimilarity handles typos using Levenshtein and Jaro-Winkler', () {
      // Typo: "Bllinding" -> "Blinding Lights"
      final typoSimilarity = StringSimilarity.fuzzyScore('Bllinding', 'Blinding Lights');
      expect(typoSimilarity, greaterThan(0.70));

      // Typo: "Arijit Sing" -> "Arijit Singh"
      final artistSimilarity = StringSimilarity.fuzzyScore('Arijit Sing', 'Arijit Singh');
      expect(artistSimilarity, greaterThan(0.85));
    });

    test('YouTubeRelevanceRanker accurately ranks by Text, Velocity, Taste, and Trend', () {
      final ranker = const YouTubeRelevanceRanker();

      final song1 = SongModel(
        id: '1',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        duration: const Duration(seconds: 200),
      );

      final song2 = SongModel(
        id: '2',
        title: 'Starboy',
        artist: 'The Weeknd',
        duration: const Duration(seconds: 230),
      );

      final song3 = SongModel(
        id: '3',
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        duration: const Duration(seconds: 240),
      );

      final ranked = ranker.rank(
        query: 'Blinding',
        candidates: [song3, song2, song1],
        globalPlayVelocityMap: {'1': 0.9, '2': 0.8, '3': 0.7},
        userFavoriteArtists: {'the weeknd'},
        trendingSongIds: {'1'},
      );

      expect(ranked.first.id, equals('1')); // Blinding Lights should be rank #1
    });

    test('YouTubeAudioFormat generates accurate quality tiers and estimates', () {
      final formats = YouTubeAudioFormat.defaults(
        streamUrl: 'https://example.com/audio.m4a',
        durationSec: 240, // 4 minutes
      );

      expect(formats.length, equals(3));
      expect(formats[0].quality, equals('High'));
      expect(formats[0].bitrate, equals('320 kbps'));
      expect(formats[1].quality, equals('Medium'));
      expect(formats[1].bitrate, equals('128 kbps'));
      expect(formats[2].quality, equals('Data Saver'));
      expect(formats[2].bitrate, equals('64 kbps'));
    });
  });
}
