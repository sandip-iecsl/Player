import 'package:flutter_test/flutter_test.dart';
import 'package:aura_player/core/search/models/search_models.dart';
import 'package:aura_player/core/search/query/query_intelligence.dart';
import 'package:aura_player/core/search/query/query_normalizer.dart';
import 'package:aura_player/core/search/query/spell_corrector.dart';
import 'package:aura_player/core/search/query/query_intent_detector.dart';
import 'package:aura_player/core/search/query/transliteration_engine.dart';
import 'package:aura_player/core/search/query/entity_extractor.dart';

void main() {
  group('Query Intelligence Suite', () {
    final intelligence = QueryIntelligence();

    test('Query Normalization strips punctuation, collapses whitespace, compresses repeated chars', () {
      expect(QueryNormalizer.normalize('  Tum   Hi... Ho!!!  '), equals('tum hi ho'));
      expect(QueryNormalizer.normalize('Arijiiit   Singhhhh'), equals('arijit singh'));
    });

    test('Spell Corrector resolves common typos and artist nicknames', () {
      expect(SpellCorrector.correct('arjit'), equals('arijit'));
      expect(SpellCorrector.correct('shreya ghosl'), equals('shreya ghoshal'));
      expect(SpellCorrector.correct('kesriya'), equals('kesariya'));
      expect(SpellCorrector.correct('taylor swft'), equals('taylor swift'));
      expect(SpellCorrector.correct('the weekend'), equals('the weeknd'));
    });

    test('Transliteration Engine resolves Hindi Devanagari and Bengali scripts to Latin', () {
      final hindiRes = TransliterationEngine.process('तुम ही हो');
      expect(hindiRes.transliterated, equals('tum hi ho'));
      expect(hindiRes.detectedLanguage, equals('hi'));

      final bengaliRes = TransliterationEngine.process('তুম হি হো');
      expect(bengaliRes.transliterated, equals('tum hi ho'));
      expect(bengaliRes.detectedLanguage, equals('bn'));
    });

    test('Intent Detector correctly classifies song, artist, live, slowed, album, discovery', () {
      expect(QueryIntentDetector.detect('arijit singh'), equals(QueryIntent.artist));
      expect(QueryIntentDetector.detect('tum hi ho arijit'), equals(QueryIntent.song));
      expect(QueryIntentDetector.detect('arijit singh live concert'), equals(QueryIntent.live));
      expect(QueryIntentDetector.detect('tum hi ho slowed reverb'), equals(QueryIntent.slowed));
      expect(QueryIntentDetector.detect('pritam albums'), equals(QueryIntent.album));
      expect(QueryIntentDetector.detect('songs like kesariya'), equals(QueryIntent.discovery));
      expect(QueryIntentDetector.detect('tum hi ho acoustic'), equals(QueryIntent.acoustic));
      expect(QueryIntentDetector.detect('tum hi ho remix'), equals(QueryIntent.remix));
    });

    test('Entity Extractor parses artist, title, version modifier, and year deterministically', () {
      final extractor = DeterministicEntityExtractor();
      final entities = extractor.extract('arijit singh tum hi ho slowed reverb 2013');

      expect(entities.artist, equals('arijit singh'));
      expect(entities.version, equals(TrackVersionType.slowed));
      expect(entities.year, equals(2013));
      expect(entities.modifiers.contains('slowed'), isTrue);
      expect(entities.modifiers.contains('reverb'), isTrue);
    });

    test('QueryIntelligence parses raw query into full ParsedQuery structure', () {
      final parsed = intelligence.parse('arjit tum hi ho slowed reverb');
      expect(parsed.raw, equals('arjit tum hi ho slowed reverb'));
      expect(parsed.intent, equals(QueryIntent.slowed));
      expect(parsed.entities.version, equals(TrackVersionType.slowed));
      expect(parsed.tokens.isNotEmpty, isTrue);
    });
  });
}
