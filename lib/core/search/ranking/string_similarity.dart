import 'dart:math';

/// String similarity algorithms for fuzzy matching and typo tolerance (Levenshtein & Jaro-Winkler)
class StringSimilarity {
  /// Computes Levenshtein edit distance between two strings
  static int levenshteinDistance(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.filled(t.length + 1, 0);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i <= t.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < t.length; j++) {
        final cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }

      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[t.length];
  }

  /// Normalized Levenshtein similarity score [0.0 - 1.0]
  static double levenshteinSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    final distance = levenshteinDistance(s1, s2);
    final maxLen = max(s1.length, s2.length);
    return (1.0 - (distance / maxLen)).clamp(0.0, 1.0);
  }

  /// Computes Jaro-Winkler distance metric [0.0 - 1.0]
  /// Optimized for prefix matches and name/title typo tolerance
  static double jaroWinkler(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final matchWindow = (max(s1.length, s2.length) / 2).floor() - 1;
    final s1Matches = List<bool>.filled(s1.length, false);
    final s2Matches = List<bool>.filled(s2.length, false);

    int matches = 0;
    for (int i = 0; i < s1.length; i++) {
      final start = max(0, i - matchWindow);
      final end = min(i + matchWindow + 1, s2.length);

      for (int j = start; j < end; j++) {
        if (s2Matches[j]) continue;
        if (s1.codeUnitAt(i) != s2.codeUnitAt(j)) continue;
        s1Matches[i] = true;
        s2Matches[j] = true;
        matches++;
        break;
      }
    }

    if (matches == 0) return 0.0;

    int transpositions = 0;
    int k = 0;
    for (int i = 0; i < s1.length; i++) {
      if (!s1Matches[i]) continue;
      while (!s2Matches[k]) {
        k++;
      }
      if (s1.codeUnitAt(i) != s2.codeUnitAt(k)) {
        transpositions++;
      }
      k++;
    }

    final double m = matches.toDouble();
    final double jaro = ((m / s1.length) + (m / s2.length) + ((m - transpositions / 2) / m)) / 3.0;

    // Winkler prefix boost (up to 4 characters prefix)
    int prefixLen = 0;
    final maxPrefix = min(4, min(s1.length, s2.length));
    for (int i = 0; i < maxPrefix; i++) {
      if (s1.codeUnitAt(i) == s2.codeUnitAt(i)) {
        prefixLen++;
      } else {
        break;
      }
    }

    const double p = 0.1; // scaling factor
    return (jaro + (prefixLen * p * (1.0 - jaro))).clamp(0.0, 1.0);
  }

  /// Composite hybrid fuzzy score combining exact prefix, Jaro-Winkler, and token overlap
  static double fuzzyScore(String query, String target) {
    final q = query.trim().toLowerCase();
    final t = target.trim().toLowerCase();

    if (q == t) return 1.0;
    if (t.startsWith(q)) return 0.95;
    if (t.contains(q)) return 0.85;

    final jw = jaroWinkler(q, t);
    final lev = levenshteinSimilarity(q, t);

    return max(jw, lev);
  }
}
