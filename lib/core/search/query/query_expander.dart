import '../../../data/services/search_enhancer.dart';
import 'query_normalizer.dart';
import 'spell_corrector.dart';
import 'transliteration_engine.dart';

/// Expands queries into search variants, synonyms, and transliterations
class QueryExpander {
  /// Expands raw query into list of high-value candidate queries
  static List<String> expand(String query) {
    final normalized = QueryNormalizer.normalize(query);
    if (normalized.isEmpty) return [];

    final result = <String>{};
    result.add(normalized);

    // 1. Spell correction
    final corrected = SpellCorrector.correct(normalized);
    if (corrected.isNotEmpty) {
      result.add(corrected);
    }

    // 2. SearchEnhancer legacy expansion
    try {
      final enhanced = SearchEnhancer.getExpandedQueries(query);
      for (final e in enhanced) {
        final n = QueryNormalizer.normalize(e);
        if (n.isNotEmpty) result.add(n);
      }
    } catch (_) {}

    // 3. Transliteration variants
    final transliterationResult = TransliterationEngine.process(query);
    if (transliterationResult.transliterated.isNotEmpty) {
      result.add(QueryNormalizer.normalize(transliterationResult.transliterated));
    }
    for (final v in transliterationResult.variants) {
      final n = QueryNormalizer.normalize(v);
      if (n.isNotEmpty) result.add(n);
    }

    return result.toList();
  }
}
