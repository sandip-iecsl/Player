/// Transliteration & Multilingual Engine for Indic scripts (Devanagari, Bengali) and Latin representations
class TransliterationEngine {
  // Common Devanagari <-> Latin direct mapping dictionary
  static const Map<String, String> _devanagariMap = {
    'तुम ही हो': 'tum hi ho',
    'केसरिया': 'kesariya',
    'अपना बना ले': 'apna bana le',
    'अरिजीत सिंह': 'arijit singh',
    'श्रेया घोषाल': 'shreya ghoshal',
    'आतिफ असलम': 'atif aslam',
    'दिलजीत दोसांझ': 'diljit dosanjh',
    'प्रीतम': 'pritam',
    'हनी सिंह': 'honey singh',
    'बादशाह': 'badshah',
    'जुबिन नौटियाल': 'jubin nautiyal',
    'तेरा बन जाऊंगा': 'tera ban jaunga',
    'कलंक': 'kalank',
    'राब्ता': 'raabta',
    'चलेया': 'chaleya',
    'पसूरी': 'pasoori',
    'सैयां': 'saiyyan',
    'कबीर सिंह': 'kabir singh',
  };

  // Common Bengali <-> Latin direct mapping dictionary
  static const Map<String, String> _bengaliMap = {
    'তুম হি হো': 'tum hi ho',
    'অরিজিৎ সিং': 'arijit singh',
    'শ্রেয়া ঘোষাল': 'shreya ghoshal',
    'কেশরিয়া': 'kesariya',
    'তুমি রবে নীরবে': 'tumi robe nirobe',
    'আমার পরাণ যাহা চায়': 'amar poran jaha chay',
    'বোঝে না সে বোঝে না': 'bozhena se bozhena',
    'তোমার খোলা হাওয়া': 'tomar khola hawa',
  };

  /// Detects if text contains Devanagari characters (\u0900 - \u097F)
  static bool isDevanagari(String text) {
    return RegExp(r'[\u0900-\u097F]').hasMatch(text);
  }

  /// Detects if text contains Bengali characters (\u0980 - \u09FF)
  static bool isBengali(String text) {
    return RegExp(r'[\u0980-\u09FF]').hasMatch(text);
  }

  /// Returns canonical Latin representation and language tag
  static ({String transliterated, String? detectedLanguage, List<String> variants}) process(String query) {
    final clean = query.trim();
    if (clean.isEmpty) {
      return (transliterated: '', detectedLanguage: null, variants: <String>[]);
    }

    final variants = <String>[clean];
    String? lang;
    String target = clean;

    if (isDevanagari(clean)) {
      lang = 'hi';
      if (_devanagariMap.containsKey(clean)) {
        target = _devanagariMap[clean]!;
        variants.add(target);
      } else {
        // Character by character phonetic approximation
        target = _approximateIndicToLatin(clean);
        variants.add(target);
      }
    } else if (isBengali(clean)) {
      lang = 'bn';
      if (_bengaliMap.containsKey(clean)) {
        target = _bengaliMap[clean]!;
        variants.add(target);
      } else {
        target = _approximateIndicToLatin(clean);
        variants.add(target);
      }
    } else {
      // Check if Latin query has a matching reverse Devanagari/Bengali equivalent
      final lower = clean.toLowerCase();
      _devanagariMap.forEach((hindi, latin) {
        if (latin == lower || lower.contains(latin)) {
          variants.add(hindi);
          if (lang == null) lang = 'hi';
        }
      });
      _bengaliMap.forEach((bengali, latin) {
        if (latin == lower || lower.contains(latin)) {
          variants.add(bengali);
          if (lang == null) lang = 'bn';
        }
      });
    }

    return (
      transliterated: target,
      detectedLanguage: lang,
      variants: variants.toSet().toList(),
    );
  }

  static String _approximateIndicToLatin(String input) {
    // Basic char transliteration mapping for fallback
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code >= 0x0905 && code <= 0x0914) {
        buffer.write('a'); // Devanagari vowels
      } else if (code >= 0x0915 && code <= 0x0939) {
        buffer.write('k'); // Devanagari consonants generic
      } else if (code >= 0x0985 && code <= 0x0994) {
        buffer.write('a'); // Bengali vowels
      } else if (code >= 0x0995 && code <= 0x09B9) {
        buffer.write('k'); // Bengali consonants generic
      } else {
        buffer.write(input[i]);
      }
    }
    return buffer.toString();
  }
}
