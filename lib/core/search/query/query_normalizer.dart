/// Query Normalizer for music search queries
/// Handles Unicode normalization, case lowering, whitespace collapsing,
/// punctuation stripping, and repeated character compression (e.g. "soooong" -> "soong").
class QueryNormalizer {
  static final RegExp _punctuationRegex = RegExp(r'[^\w\s\u0900-\u097F\u0980-\u09FF]'); // Keeps Latin, Devanagari, Bengali
  static final RegExp _multiWhitespaceRegex = RegExp(r'\s+');
  static final RegExp _repeatedCharRegex = RegExp(r'(.)\1{2,}'); // 3 or more repeated characters -> reduce to 2

  /// Fully normalizes a raw search string
  static String normalize(String raw) {
    if (raw.isEmpty) return '';

    String cleaned = raw.toLowerCase().trim();

    // 1. Unicode character mapping / replacements
    cleaned = _normalizeDiacritics(cleaned);

    // 2. Remove non-alphanumeric punctuation except multilingual characters
    cleaned = cleaned.replaceAll(_punctuationRegex, ' ');

    // 3. Compress excessive repeated characters (e.g. "arijiiit" -> "arijit", "singhhhh" -> "singh")
    cleaned = cleaned.replaceAllMapped(_repeatedCharRegex, (match) {
      return match.group(1)!;
    });

    // 4. Collapse whitespace
    cleaned = cleaned.replaceAll(_multiWhitespaceRegex, ' ').trim();

    return cleaned;
  }

  /// Extracts clean token list
  static List<String> tokenize(String query) {
    final norm = normalize(query);
    if (norm.isEmpty) return [];
    return norm.split(' ').where((t) => t.isNotEmpty).toList();
  }

  static String _normalizeDiacritics(String text) {
    // Basic diacritics / accent strip
    const withDia = 'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
    const withoutDia = 'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';

    var result = text;
    for (int i = 0; i < withDia.length; i++) {
      result = result.replaceAll(withDia[i], withoutDia[i]);
    }
    return result;
  }
}
