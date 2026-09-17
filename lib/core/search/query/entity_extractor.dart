import '../models/search_models.dart';
import 'query_normalizer.dart';
import 'transliteration_engine.dart';

/// Abstract Entity Extractor interface allowing AI/LLM models or Deterministic models to be swapped in
abstract interface class EntityExtractor {
  QueryEntities extract(String query);
}

/// Deterministic Entity Extractor for music search queries
class DeterministicEntityExtractor implements EntityExtractor {
  static const List<String> _knownArtists = [
    'arijit singh', 'shreya ghoshal', 'atif aslam', 'armaan malik', 'diljit dosanjh',
    'pritam', 'anirudh ravichander', 'anirudh', 'sidhu moose wala', 'badshah',
    'honey singh', 'yo yo honey singh', 'jubin nautiyal', 'neha kakkar', 'sonu nigam',
    'k k', 'mohit chauhan', 'sunidhi chauhan', 'kumar sanu', 'alka yagnik', 'lata mangeshkar',
    'kishore kumar', 'taylor swift', 'ed sheeran', 'eminem', 'the weeknd', 'post malone',
    'billie eilish', 'drake', 'justin bieber', 'dua lipa', 'bruno mars', 'adele', 'coldplay',
    'imagine dragons', 'charlie puth', 'selena gomez', 'ariana grande', 'alan walker'
  ];

  static const List<String> _knownAlbums = [
    'aashiqui 2', 'brahmastra', 'kabir singh', 'animal', 'rockstar', 'ye jawani hai deewani',
    'kalank', 'raabta', 'ae dil hai mushkil', 'jab we met', 'divide', 'midnights', '1989',
    'starboy', 'after hours', 'beerbongs and bentleys', 'astroworld', 'scary monsters'
  ];

  static final RegExp _yearRegex = RegExp(r'\b(19\d{2}|20\d{2})\b');

  @override
  QueryEntities extract(String query) {
    final normalized = QueryNormalizer.normalize(query);
    if (normalized.isEmpty) return const QueryEntities();

    String remaining = normalized;
    String? matchedArtist;
    String? matchedAlbum;
    int? matchedYear;
    String? detectedLanguage;
    TrackVersionType? matchedVersion;
    final modifiers = <String>[];

    // 1. Language detection from script
    if (TransliterationEngine.isDevanagari(query)) {
      detectedLanguage = 'hi';
    } else if (TransliterationEngine.isBengali(query)) {
      detectedLanguage = 'bn';
    }

    // 2. Extract Year
    final yearMatch = _yearRegex.firstMatch(remaining);
    if (yearMatch != null) {
      matchedYear = int.tryParse(yearMatch.group(1)!);
      remaining = remaining.replaceAll(yearMatch.group(0)!, '').trim();
    }

    // 3. Extract Version / Modifiers
    if (remaining.contains('slowed reverb') || remaining.contains('slowed and reverb')) {
      matchedVersion = TrackVersionType.slowed;
      modifiers.addAll(['slowed', 'reverb']);
      remaining = remaining.replaceAll(RegExp(r'\bslowed(\s+and)?\s+reverb\b'), '').trim();
    } else if (remaining.contains('slowed')) {
      matchedVersion = TrackVersionType.slowed;
      modifiers.add('slowed');
      remaining = remaining.replaceAll(RegExp(r'\bslowed\b'), '').trim();
    } else if (remaining.contains('reverb')) {
      matchedVersion = TrackVersionType.slowed;
      modifiers.add('reverb');
      remaining = remaining.replaceAll(RegExp(r'\breverb\b'), '').trim();
    }

    if (remaining.contains('remix')) {
      matchedVersion = TrackVersionType.remix;
      modifiers.add('remix');
      remaining = remaining.replaceAll(RegExp(r'\bremix\b'), '').trim();
    } else if (remaining.contains('mashup')) {
      matchedVersion = TrackVersionType.remix;
      modifiers.add('mashup');
      remaining = remaining.replaceAll(RegExp(r'\bmashup\b'), '').trim();
    } else if (remaining.contains('live') || remaining.contains('concert') || remaining.contains('unplugged')) {
      matchedVersion = TrackVersionType.live;
      modifiers.add('live');
      remaining = remaining.replaceAll(RegExp(r'\b(live|concert|unplugged)\b'), '').trim();
    } else if (remaining.contains('acoustic')) {
      matchedVersion = TrackVersionType.acoustic;
      modifiers.add('acoustic');
      remaining = remaining.replaceAll(RegExp(r'\bacoustic\b'), '').trim();
    } else if (remaining.contains('lofi') || remaining.contains('lo fi')) {
      matchedVersion = TrackVersionType.lofi;
      modifiers.add('lofi');
      remaining = remaining.replaceAll(RegExp(r'\blo\s*fi\b'), '').trim();
    } else if (remaining.contains('cover')) {
      matchedVersion = TrackVersionType.cover;
      modifiers.add('cover');
      remaining = remaining.replaceAll(RegExp(r'\bcover\b'), '').trim();
    } else if (remaining.contains('karaoke') || remaining.contains('instrumental')) {
      matchedVersion = TrackVersionType.karaoke;
      modifiers.add('karaoke');
      remaining = remaining.replaceAll(RegExp(r'\b(karaoke|instrumental)\b'), '').trim();
    } else if (remaining.contains('lyrics') || remaining.contains('lyric')) {
      matchedVersion = TrackVersionType.lyrics;
      modifiers.add('lyrics');
      remaining = remaining.replaceAll(RegExp(r'\blyrics?\b'), '').trim();
    }

    // 4. Extract Artist
    for (final artist in _knownArtists) {
      if (remaining.contains(artist)) {
        matchedArtist = artist;
        remaining = remaining.replaceAll(artist, '').trim();
        break;
      }
    }

    // 5. Extract Album
    for (final album in _knownAlbums) {
      if (remaining.contains(album)) {
        matchedAlbum = album;
        remaining = remaining.replaceAll(album, '').trim();
        break;
      }
    }

    // Clean remaining tokens to get candidate title
    String candidateTitle = remaining.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (candidateTitle.isEmpty && matchedArtist != null) {
      // Query was only the artist
      candidateTitle = '';
    }

    return QueryEntities(
      artist: matchedArtist,
      title: candidateTitle.isNotEmpty ? candidateTitle : null,
      album: matchedAlbum,
      year: matchedYear,
      language: detectedLanguage,
      version: matchedVersion,
      modifiers: modifiers,
    );
  }
}
