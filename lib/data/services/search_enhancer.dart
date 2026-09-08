import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class SearchEnhancer {
  /// Synchronizes all ML Engine mappings from Firestore to the local Hive box silently
  static Future<void> syncFromFirestore() async {
    // Disabled temporarily by returning early to avoid Firestore reads
    return;
  }
  // Common typo and synonym mappings (built-in defaults)
  static const Map<String, String> _defaultSynonyms = {
    // Typos & Shortcuts — Bollywood/Hindi
    'juben': 'jubin nautiyal',
    'jubin': 'jubin nautiyal',
    'jubeen': 'jubin nautiyal',
    'aaradhya': 'aradhya',
    'arijit': 'arijit singh',
    'arijt': 'arijit singh',
    'arijeet': 'arijit singh',
    'ari': 'arijit singh',
    'sonu': 'sonu nigam',
    'shreya': 'shreya ghoshal',
    'shreya goshal': 'shreya ghoshal',
    'shreya gosal': 'shreya ghoshal',
    'lata': 'lata mangeshkar',
    'lata mangeshwar': 'lata mangeshkar',
    'kishore': 'kishore kumar',
    'nay': 'naina',
    'neha': 'neha kakkar',
    'neha kakar': 'neha kakkar',
    'tony': 'tony kakkar',
    'badshah': 'badshah',
    'honey': 'yo yo honey singh',
    'honey singh': 'yo yo honey singh',
    'yo yo': 'yo yo honey singh',
    'atif': 'atif aslam',
    'atif aslam songs': 'atif aslam',
    'armaan': 'armaan malik',
    'darshan': 'darshan raval',
    'darshan rawal': 'darshan raval',
    'vishal': 'vishal mishra',
    'kk': 'kk singer',
    'mohit': 'mohit chauhan',
    'sunidhi': 'sunidhi chauhan',
    'sunidhi chouhan': 'sunidhi chauhan',
    'shankar': 'shankar mahadevan',
    'udit': 'udit narayan',
    'kumar': 'kumar sanu',
    'asha': 'asha bhosle',
    'asha bhonsle': 'asha bhosle',
    'rafi': 'mohammad rafi',
    'moh rafi': 'mohammad rafi',
    'mukesh': 'mukesh singer',
    'hemant': 'hemant kumar',
    // Punjabi
    'diljit': 'diljit dosanjh',
    'diljeet': 'diljit dosanjh',
    'ap': 'ap dhillon',
    'sidhu': 'sidhu moose wala',
    'moose': 'sidhu moose wala',
    'guru': 'guru randhawa',
    'b praak': 'b praak',
    'satinder': 'satinder sartaaj',
    'ammy': 'ammy virk',
    'jasmine': 'jasmine sandlas',
    'jasmeen': 'jasmine sandlas',
    // South Indian
    'anirudh': 'anirudh ravichander',
    'dhanush': 'dhanush singer',
    'sid sriram': 'sid sriram',
    'sid': 'sid sriram',
    'sp': 's p balasubrahmanyam',
    'balu': 's p balasubrahmanyam',
    'spb': 's p balasubrahmanyam',
    'harris': 'harris jayaraj',
    'ar': 'a r rahman',
    'ar rahman': 'a r rahman',
    'rahman': 'a r rahman',
    // English shortcuts
    'ed': 'ed sheeran',
    'taylor': 'taylor swift',
    'ts': 'taylor swift',
    'bts': 'bts kpop',
    'eminem': 'eminem',
    'slim': 'eminem',
    'weekend': 'the weeknd',
    'weeknd': 'the weeknd',
    'abel': 'the weeknd',
  };

  static Map<String, String>? _cachedAliases;
  static List<String>? _cachedSortedKeys;
  static int _lastBoxLength = -1;

  static void _ensureCache() {
    final box = Hive.isBoxOpen('ml_training_box') ? Hive.box('ml_training_box') : null;
    final currentLength = box?.length ?? 0;
    
    // Rebuild cache if it's null or the database size changed
    if (_cachedAliases == null || _cachedSortedKeys == null || _lastBoxLength != currentLength) {
      _cachedAliases = Map.from(_defaultSynonyms);
      if (box != null) {
        for (final key in box.keys) {
          _cachedAliases![key.toString().toLowerCase().trim()] = box.get(key).toString().toLowerCase().trim();
        }
      }
      // Pre-sort keys by length descending for substring replacement
      _cachedSortedKeys = _cachedAliases!.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
      _lastBoxLength = currentLength;
    }
  }

  /// Returns a normalized, corrected version of the query.
  /// If the query contains a known synonym/typo or custom trained phrase, it returns the corrected version.
  static String enhanceQuery(String query) {
    if (query.trim().isEmpty) return query;
    
    _ensureCache();
    final lowerQuery = query.toLowerCase().trim();
    
    // 1. Check for exact full-query synonym match (highest priority)
    if (_cachedAliases!.containsKey(lowerQuery)) {
      return _cachedAliases![lowerQuery]!;
    }
    
    // 2. Check for substring replacements (e.g. if the query CONTAINS a trained phrase)
    String replacedQuery = lowerQuery;
    bool substringChanged = false;
    
    for (final key in _cachedSortedKeys!) {
      if (key.contains(' ') && replacedQuery.contains(key)) { // Only substring-replace multi-word trained phrases to avoid breaking words
        replacedQuery = replacedQuery.replaceAll(key, _cachedAliases![key]!);
        substringChanged = true;
      }
    }
    
    if (substringChanged) {
      return replacedQuery.trim();
    }
    
    // 3. Word-by-word replacement for single-word synonyms (basic typo replacement like "juben" -> "jubin nautiyal")
    final words = lowerQuery.split(' ');
    bool changed = false;
    for (int i = 0; i < words.length; i++) {
      if (_cachedAliases!.containsKey(words[i])) {
        words[i] = _cachedAliases![words[i]]!;
        changed = true;
      }
    }
    
    if (changed) {
      return words.join(' ');
    }
    
    return query;
  }
  
  /// Get a list of expanded queries to search for.
  /// This is useful for short queries where we want to search the literal short query
  /// AND the expanded synonym simultaneously to merge results.
  static List<String> getExpandedQueries(String query) {
    if (query.trim().isEmpty) return [query];
    
    final lowerQuery = query.toLowerCase().trim();
    final enhanced = enhanceQuery(query);
    
    if (enhanced.toLowerCase() != lowerQuery) {
      return [lowerQuery, enhanced];
    }
    
    return [query];
  }
}
