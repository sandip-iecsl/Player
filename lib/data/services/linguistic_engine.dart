import 'package:flutter/foundation.dart';
import '../../domain/entities/song.dart';

/// Linguistic Engine
/// Optimizes the recommendation pipeline to respect regional language affinity,
/// cross-language leakage, and regional market trends within India.
class LinguisticEngine {
  // Track consecutive plays of a single language to prevent silos
  String? _currentLanguageSilo;
  int _consecutiveLanguageCount = 0;

  // Simple hardcoded mapping to infer language from artist or title if API lacks it
  // In a real prod app, this would be far more exhaustive.
  final Map<String, String> _artistLanguageMap = {
    'arijit singh': 'hindi',
    'shreya ghoshal': 'hindi',
    'alka yagnik': 'hindi',
    'udit narayan': 'hindi',
    'kumar sanu': 'hindi',
    'diljit dosanjh': 'punjabi',
    'ap dhillon': 'punjabi',
    'guru randhawa': 'punjabi',
    'b praak': 'punjabi',
    'pawan singh': 'bhojpuri',
    'khesari lal yadav': 'bhojpuri',
    'shilpi raj': 'bhojpuri',
    'anupam roy': 'bengali',
    'rupanakr': 'bengali',
    'shaan': 'hindi', // Shaan sings Bengali too, but mostly Hindi
    'sidhu moose wala': 'punjabi',
  };

  /// Inferred phonetic dictionaries for token-based NLP language classification
  static const Map<String, Set<String>> _phoneticDictionaries = {
    'hindi': {
      'pyar', 'pyaar', 'dil', 'mera', 'ishq', 'teri', 'tere', 'meri', 'tujhe', 'tum', 
      'se', 'hai', 'ki', 'ka', 'ke', 'aur', 'na', 'jiya', 'dhadkan', 'sanam', 'tu', 'mujhse', 'hum', 
      'tumhare', 'zindagi', 'mohabbat', 'dost', 'yaar', 'yaara', 'jaane', 'jaana', 'raahi', 'ho', 'gaya',
      'ek', 'do', 'teen', 'main', 'hoon', 'kya', 'batayein', 'kaise', 'mile', 'chalte', 'duniya', 'dhadak'
    },
    'punjabi': {
      'kudi', 'munda', 'gabru', 'pind', 'punjabi', 'jatt', 've', 'bhangra', 'dhol', 'nach', 'suit', 
      'nakhra', 'gaddi', 'gaddiyaan', 'mittran', 'ni', 'hath', 'sardar', 'singh', 'kaur', 'panjabo',
      'naal', 'changa', 'vadiya', 'kol', 'chadd', 'viah', 'je', 'patiala'
    },
    'bhojpuri': {
      'kamariya', 'lagawe', 'lipistick', 'lipistik', 'bhojpuri', 'gori', 'tohar', 'ba', 'laika', 
      'choli', 'bhatar', 'sautin', 'patna', 'pawan', 'khesari', 'lahanga', 'marad', 'maro', 'saiyaan', 
      'bhojpuria', 'tore', 'maai', 'piya', 'kajar', 'luliya', 'hamar'
    },
    'bengali': {
      'bengali', 'bangla', 'tumi', 'aami', 'bhalobashi', 'amar', 'tomar', 'kothay', 'mon', 'bhalo', 
      'shundor', 'gaan', 'brishti', 'shonar', 'chaai', 'hobe', 'kotha', 'dekha', 'bhalobasa', 'golpo',
      'bhalobese', 'moner', 'kache', 'chara', 'keu'
    },
  };

  /// Infer the language of a song with cascading lookup hierarchy:
  /// 1. Direct song metadata check
  /// 2. Artist profile matching
  /// 3. Hinglish/phonetic token text analysis
  /// 4. Substring fallback checks
  /// 5. Global fallback
  String inferLanguage(Song song) {
    // 1. Direct song language check
    if (song.language != null && song.language!.isNotEmpty) {
      final lang = song.language!.toLowerCase();
      if (lang.contains('hindi') || lang == 'hi') return 'hindi';
      if (lang.contains('punjabi') || lang == 'pa') return 'punjabi';
      if (lang.contains('bhojpuri')) return 'bhojpuri';
      if (lang.contains('bengali') || lang == 'bn') return 'bengali';
      return lang;
    }

    final titleLower = song.title.toLowerCase();
    final artistLower = song.artist.toLowerCase();

    // 2. Artist profile check
    for (final entry in _artistLanguageMap.entries) {
      if (artistLower.contains(entry.key)) {
        return entry.value;
      }
    }

    // 3. Token-based phonetic dictionary analysis
    final tokens = titleLower.split(RegExp(r'[^a-zA-Z0-9]+')).where((t) => t.isNotEmpty);
    final scores = <String, int>{'hindi': 0, 'punjabi': 0, 'bhojpuri': 0, 'bengali': 0};

    for (final token in tokens) {
      for (final lang in _phoneticDictionaries.keys) {
        if (_phoneticDictionaries[lang]!.contains(token)) {
          scores[lang] = scores[lang]! + 1;
        }
      }
    }

    String? bestLang;
    int maxScore = 0;
    scores.forEach((lang, score) {
      if (score > maxScore) {
        maxScore = score;
        bestLang = lang;
      }
    });

    if (maxScore > 0 && bestLang != null) {
      return bestLang!;
    }

    // 4. Substring fallback checks
    if (titleLower.contains('bhojpuri')) return 'bhojpuri';
    if (titleLower.contains('punjabi')) return 'punjabi';
    if (titleLower.contains('bengali') || titleLower.contains('bangla')) return 'bengali';

    // 5. Default fallback
    return 'hindi';
  }

  /// Calculates the linguistic weight modifier for a candidate song.
  /// 
  /// - Applies a 1.5x multiplier if it matches the user's inferred region profile.
  /// - Applies Cross-Language Leakage bridges.
  /// - Prevents Silos by penalizing after 4 consecutive tracks.
  double getLinguisticModifier(Song seedSong, Song candidateSong) {
    final seedLang = inferLanguage(seedSong);
    final candidateLang = inferLanguage(candidateSong);

    // Track consecutive plays (simplified state management for the engine)
    if (seedLang == _currentLanguageSilo) {
      _consecutiveLanguageCount++;
    } else {
      _currentLanguageSilo = seedLang;
      _consecutiveLanguageCount = 1;
    }

    double modifier = 1.0;

    // 1. Linguistic Weighting
    if (candidateLang == seedLang) {
      modifier *= 1.5;
    }

    // 2. Silo Prevention
    if (_consecutiveLanguageCount >= 4 && candidateLang == seedLang) {
      // Force injection of a neighboring language pool by penalizing the current language
      debugPrint('[LinguisticEngine] 🛑 Silo detected! Penalizing $seedLang to force a bridge track.');
      modifier *= 0.3; 
    } else if (_consecutiveLanguageCount >= 4 && candidateLang != seedLang) {
      // Boost neighboring language to break the silo
      modifier *= 2.0;
    }

    // 3. Cross-Language Leakage Bridges
    if (seedLang == 'hindi' && candidateLang == 'punjabi') {
      // High-energy Punjabi leaks naturally into Hindi
      modifier *= 1.3;
    } else if (seedLang == 'hindi' && candidateLang == 'bhojpuri') {
      modifier *= 1.2;
    } else if (seedLang == 'bengali' && candidateLang == 'hindi') {
      // Slow acoustic Hindi romantic ballads blend nicely with Bengali
      modifier *= 1.4;
    } else if (seedLang == 'bhojpuri' && candidateLang == 'hindi') {
      // Bhojpuri transitions smoothly to mainstream Bollywood
      modifier *= 1.3;
    }

    return modifier;
  }

  void resetSilo() {
    _currentLanguageSilo = null;
    _consecutiveLanguageCount = 0;
  }
}
