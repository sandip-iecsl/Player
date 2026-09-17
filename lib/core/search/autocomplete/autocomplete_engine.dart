import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../query/query_normalizer.dart';
import '../query/spell_corrector.dart';
import '../ranking/string_similarity.dart';
import 'autocomplete_index.dart';

/// Autocomplete Engine providing instant local search recommendations
class AutocompleteEngine {
  final AutocompleteIndex _index = AutocompleteIndex();
  bool _isInitialized = false;

  static const List<String> _seedSuggestions = [
    'arijit singh', 'arijit singh songs', 'tum hi ho', 'kesariya', 'apna bana le',
    'shreya ghoshal', 'atif aslam', 'diljit dosanjh', 'pritam', 'anirudh',
    'sidhu moose wala', 'badshah', 'honey singh', 'jubin nautiyal', 'believer',
    'despacito', 'taylor swift', 'ed sheeran', 'eminem', 'the weeknd', 'starboy',
    'shape of you', 'chaleya', 'pasoori', 'kabir singh songs', 'aashiqui 2 songs'
  ];

  Future<void> init() async {
    if (_isInitialized) return;

    _index.insertAll(_seedSuggestions);

    // 1. Populate from search history box
    if (Hive.isBoxOpen('searchHistory')) {
      final box = Hive.box<String>('searchHistory');
      for (final val in box.values) {
        _index.insert(val);
      }
    }

    // 2. Populate from listening history
    if (Hive.isBoxOpen('listening_history')) {
      final box = Hive.box('listening_history');
      final artists = box.get('artists') as Map? ?? {};
      for (final a in artists.keys) {
        _index.insert(a.toString());
      }
    }

    // 3. Populate from downloaded offline songs
    if (Hive.isBoxOpen('offline_songs')) {
      final box = Hive.box('offline_songs');
      for (final key in box.keys) {
        final val = box.get(key);
        if (val != null) {
          try {
            final Map json = val is String ? jsonDecode(val) : val as Map;
            if (json['title'] != null) _index.insert(json['title'].toString());
            if (json['artist'] != null) _index.insert(json['artist'].toString());
          } catch (_) {}
        }
      }
    }

    _isInitialized = true;
  }

  /// Suggests completions in real-time (<50ms)
  List<String> getSuggestions(String query, {int limit = 6}) {
    final clean = QueryNormalizer.normalize(query);
    if (clean.isEmpty) return [];

    if (!_isInitialized) {
      _index.insertAll(_seedSuggestions);
    }

    final suggestions = <String>{};

    // 1. Prefix matches from Trie
    final prefixMatches = _index.lookupPrefix(clean, limit: limit);
    suggestions.addAll(prefixMatches);

    // 2. Exact Spell Correction
    final corrected = SpellCorrector.correct(clean);
    if (corrected != clean && corrected.isNotEmpty) {
      suggestions.add(corrected);
    }

    // 3. Fuzzy search if Trie returned few results
    if (suggestions.length < limit) {
      for (final entry in _index.allEntries) {
        if (suggestions.contains(entry)) continue;
        final sim = StringSimilarity.levenshteinSimilarity(clean, entry);
        if (sim >= 0.65 || entry.contains(clean)) {
          suggestions.add(entry);
          if (suggestions.length >= limit) break;
        }
      }
    }

    return suggestions.take(limit).toList();
  }
}
