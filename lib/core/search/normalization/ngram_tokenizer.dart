/// Text Normalization and N-Gram Tokenization Pipeline for Firestore Free-Tier Search
/// 
/// Generates deterministic prefix N-grams, edge grams, and word tokens
/// to support substring and autocomplete searches via Firestore `array-contains` queries.
class NGramTokenizer {
  static const int minGramSize = 2;
  static const int maxGramSize = 10;

  /// Normalizes a string by lowercasing, stripping diacritics/accents, and removing special symbols
  static String normalize(String input) {
    var text = input.trim().toLowerCase();
    
    // Replace common diacritics
    const diacritics = 'àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿ';
    const replacements = 'aaaaaaeceeeeiiiinoooooouuuuyy';
    for (int i = 0; i < diacritics.length; i++) {
      text = text.replaceAll(diacritics[i], replacements[i]);
    }

    // Replace punctuation with spaces
    text = text.replaceAll(RegExp(r'[\.,\/#!$%\^&\*;:{}=\-_`~()\[\]"?]'), ' ');
    // Collapse multiple spaces into one
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Generates N-Gram token array for Firestore indexing from track title, artist, and album
  static List<String> generateSearchTokens({
    required String title,
    required String artist,
    String? album,
  }) {
    final tokens = <String>{};

    final normalizedTitle = normalize(title);
    final normalizedArtist = normalize(artist);
    final normalizedAlbum = album != null ? normalize(album) : '';

    final combinedFields = [normalizedTitle, normalizedArtist, normalizedAlbum]
        .where((s) => s.isNotEmpty)
        .toList();

    for (final field in combinedFields) {
      // 1. Whole field edge grams (e.g. "bl", "bli", "blin", "blind", "blindi", "blindin", "blinding")
      _addEdgeGrams(field, tokens);

      // 2. Word-level tokens and word edge grams
      final words = field.split(' ');
      for (final word in words) {
        if (word.isEmpty) continue;
        tokens.add(word);
        _addEdgeGrams(word, tokens);
      }
    }

    // Return capped token set to stay well within Firestore 1MB document size limit
    return tokens.take(150).toList();
  }

  /// Adds prefix edge grams from minGramSize up to maxGramSize
  static void _addEdgeGrams(String text, Set<String> tokens) {
    final len = text.length;
    final maxLen = len < maxGramSize ? len : maxGramSize;
    for (int i = minGramSize; i <= maxLen; i++) {
      tokens.add(text.substring(0, i));
    }
  }
}
