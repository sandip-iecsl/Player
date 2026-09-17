import '../models/search_models.dart';
import 'entity_extractor.dart';
import 'query_expander.dart';
import 'query_intent_detector.dart';
import 'query_normalizer.dart';
import 'spell_corrector.dart';
import 'transliteration_engine.dart';

/// Central Query Intelligence Engine
/// Transforms raw user input into an enriched ParsedQuery
class QueryIntelligence {
  final EntityExtractor _entityExtractor;

  QueryIntelligence({EntityExtractor? entityExtractor})
      : _entityExtractor = entityExtractor ?? DeterministicEntityExtractor();

  /// Parses and enhances raw search query
  ParsedQuery parse(String rawQuery) {
    final raw = rawQuery.trim();
    if (raw.isEmpty) {
      return const ParsedQuery(
        raw: '',
        normalized: '',
        corrected: '',
        intent: QueryIntent.unknown,
        entities: QueryEntities(),
      );
    }

    // 1. Transliteration & Multilingual handling
    final transliteration = TransliterationEngine.process(raw);
    final baseText = transliteration.transliterated.isNotEmpty ? transliteration.transliterated : raw;

    // 2. Normalization
    final normalized = QueryNormalizer.normalize(baseText);

    // 3. Spell Correction
    final corrected = SpellCorrector.correct(normalized);

    // 4. Intent Detection
    final effectiveQuery = corrected.isNotEmpty ? corrected : normalized;
    final intent = QueryIntentDetector.detect(effectiveQuery);

    // 5. Entity Extraction
    final entities = _entityExtractor.extract(effectiveQuery);

    // 6. Tokenization
    final tokens = QueryNormalizer.tokenize(effectiveQuery);

    // 7. Expansion & synonyms
    final expansions = QueryExpander.expand(raw);

    return ParsedQuery(
      raw: raw,
      normalized: normalized,
      corrected: corrected,
      intent: intent,
      entities: entities,
      detectedLanguage: transliteration.detectedLanguage ?? entities.language,
      transliteratedVariants: transliteration.variants,
      synonyms: expansions,
      tokens: tokens,
    );
  }
}
