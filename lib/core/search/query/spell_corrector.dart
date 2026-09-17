import 'package:hive_flutter/hive_flutter.dart';
import '../ranking/string_similarity.dart';
import 'query_normalizer.dart';

/// Spell corrector for music domain entities, artist names, and popular song terms
class SpellCorrector {
  // Built-in dictionary of prominent artist & song tokens
  static const Map<String, String> _knownAliases = {
    'arjit': 'arijit',
    'arjit singh': 'arijit singh',
    'shreya ghosl': 'shreya ghoshal',
    'shreya ghosal': 'shreya ghoshal',
    'arijit sing': 'arijit singh',
    'atif aslm': 'atif aslam',
    'armaan mlik': 'armaan malik',
    'diljit dosanj': 'diljit dosanjh',
    'pritam chakraborty': 'pritam',
    'anirudh ravichander': 'anirudh',
    'sidhu moosewala': 'sidhu moose wala',
    'badsaah': 'badshah',
    'yo yo honey singh': 'honey singh',
    'jubin nautyl': 'jubin nautiyal',
    'kesriya': 'kesariya',
    'pasoori nu': 'pasoori',
    'chaleya': 'chaleya',
    'tera ban jaunga': 'tera ban jaunga',
    'tum hi ho': 'tum hi ho',
    'apna bana le': 'apna bana le',
    'believer': 'believer',
    'despacito': 'despacito',
    'shape of you': 'shape of you',
    'taylor swft': 'taylor swift',
    'ed sheran': 'ed sheeran',
    'eminam': 'eminem',
    'the weekend': 'the weeknd',
    'post malon': 'post malone',
    'billie eilishh': 'billie eilish',
    'drakee': 'drake',
  };

  static const List<String> _dictionaryWords = [
    'arijit', 'singh', 'shreya', 'ghoshal', 'atif', 'aslam', 'armaan', 'malik',
    'diljit', 'dosanjh', 'pritam', 'anirudh', 'sidhu', 'moose', 'wala', 'badshah',
    'honey', 'jubin', 'nautiyal', 'kesariya', 'pasoori', 'chaleya', 'believer',
    'despacito', 'taylor', 'swift', 'ed', 'sheeran', 'eminem', 'weeknd', 'post',
    'malone', 'billie', 'eilish', 'drake', 'album', 'remix', 'acoustic', 'unplugged',
    'soundtrack', 'lyrics', 'official', 'slowed', 'reverb', 'lofi', 'live', 'song'
  ];

  static const Set<String> _commonWords = {
    'like', 'songs', 'song', 'music', 'best', 'top', 'the', 'and', 'to', 'of',
    'in', 'for', 'with', 'by', 'from', 'all', 'new', 'old', 'hit', 'hits',
    'audio', 'video', 'full', 'track', 'soundtrack', 'original', 'version'
  };

  /// Corrects spelling of query using dictionary, alias map, and local trained Hive rules
  static String correct(String query) {
    final normalized = QueryNormalizer.normalize(query);
    if (normalized.isEmpty) return '';

    // 1. Check exact phrase in known aliases
    if (_knownAliases.containsKey(normalized)) {
      return _knownAliases[normalized]!;
    }

    // 2. Check admin-trained Hive box (ml_training_box)
    if (Hive.isBoxOpen('ml_training_box')) {
      final box = Hive.box('ml_training_box');
      if (box.containsKey(normalized)) {
        final val = box.get(normalized)?.toString();
        if (val != null && val.isNotEmpty) return val;
      }
    }

    // 3. Word-by-word typo correction
    final tokens = normalized.split(' ');
    final correctedTokens = <String>[];

    for (final token in tokens) {
      if (_knownAliases.containsKey(token)) {
        correctedTokens.add(_knownAliases[token]!);
        continue;
      }

      if (_commonWords.contains(token)) {
        correctedTokens.add(token);
        continue;
      }

      // Check admin box for single token
      if (Hive.isBoxOpen('ml_training_box')) {
        final box = Hive.box('ml_training_box');
        if (box.containsKey(token)) {
          final val = box.get(token)?.toString();
          if (val != null && val.isNotEmpty) {
            correctedTokens.add(val);
            continue;
          }
        }
      }

      // Fuzzy check against dictionary
      String bestCandidate = token;
      double highestSim = 0.0;

      for (final dictWord in _dictionaryWords) {
        final sim = StringSimilarity.levenshteinSimilarity(token, dictWord);
        // Only correct if edit distance is close (similarity >= 0.75 for tokens > 3 chars)
        if (sim >= 0.75 && token.length > 3 && sim > highestSim) {
          highestSim = sim;
          bestCandidate = dictWord;
        }
      }

      correctedTokens.add(bestCandidate);
    }

    return correctedTokens.join(' ');
  }
}
