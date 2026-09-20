import '../models/search_models.dart';
import '../query/spell_corrector.dart';

/// Generates "Did you mean?" suggestions for search queries
class DidYouMeanEngine {
  /// Generates a "Did you mean?" suggestion if the query was corrected and differs from the input
  static String? evaluate({
    required ParsedQuery query,
    required List<RankedCandidate> topResults,
  }) {
    if (query.raw.trim().isEmpty) return null;

    final norm = query.normalized;
    final corrected = query.corrected;

    // If query had a typo that was corrected
    if (corrected.isNotEmpty && corrected != norm) {
      // Capitalize nicely
      return _capitalizeWords(corrected);
    }

    // If top result is a strong exact match to raw query, do not show "Did you mean?"
    if (topResults.isNotEmpty && topResults.first.finalScore >= 0.75) {
      return null;
    }

    // Check SpellCorrector directly
    final directCorrection = SpellCorrector.correct(norm);
    if (directCorrection.isNotEmpty && directCorrection != norm) {
      return _capitalizeWords(directCorrection);
    }

    return null;
  }

  static String _capitalizeWords(String text) {
    return text.split(' ').map((w) {
      if (w.isEmpty) return '';
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }).join(' ');
  }
}
