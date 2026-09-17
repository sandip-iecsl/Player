import '../models/search_models.dart';
import 'query_normalizer.dart';

/// Intent Detector for search queries
class QueryIntentDetector {
  static const List<String> _knownArtists = [
    'arijit singh', 'arijit', 'shreya ghoshal', 'shreya', 'atif aslam', 'atif',
    'armaan malik', 'diljit dosanjh', 'diljit', 'pritam', 'anirudh', 'sidhu moose wala',
    'badshah', 'honey singh', 'jubin nautiyal', 'neha kakkar', 'sonu nigam',
    'taylor swift', 'ed sheeran', 'eminem', 'the weeknd', 'post malone',
    'billie eilish', 'drake', 'justin bieber', 'dua lipa', 'bruno mars'
  ];

  /// Detects the primary QueryIntent from normalized query string
  static QueryIntent detect(String query) {
    final normalized = QueryNormalizer.normalize(query);
    if (normalized.isEmpty) return QueryIntent.unknown;

    // 1. Discovery / Similar Intent
    if (normalized.startsWith('songs like') ||
        normalized.startsWith('similar to') ||
        normalized.startsWith('recommendations for') ||
        normalized.contains('more like')) {
      return QueryIntent.discovery;
    }

    // 2. Lyrics Intent
    if (RegExp(r'\b(lyrics|lyric)\b').hasMatch(normalized)) {
      return QueryIntent.lyrics;
    }

    // 3. Live Intent
    if (RegExp(r'\b(live|concert|unplugged)\b').hasMatch(normalized)) {
      return QueryIntent.live;
    }

    // 4. Slowed / Reverb Intent
    if (RegExp(r'\b(slowed|reverb)\b').hasMatch(normalized)) {
      return QueryIntent.slowed;
    }

    // 5. Lofi Intent
    if (RegExp(r'\b(lofi|lo-fi|chillhop)\b').hasMatch(normalized)) {
      return QueryIntent.lofi;
    }

    // 6. Remix Intent
    if (RegExp(r'\b(remix|mashup|club edit)\b').hasMatch(normalized)) {
      return QueryIntent.remix;
    }

    // 7. Acoustic Intent
    if (RegExp(r'\b(acoustic|piano version|guitar version)\b').hasMatch(normalized)) {
      return QueryIntent.acoustic;
    }

    // 8. Cover Intent
    if (RegExp(r'\b(cover|female version|male version)\b').hasMatch(normalized)) {
      return QueryIntent.cover;
    }

    // 9. Karaoke Intent
    if (RegExp(r'\b(karaoke|instrumental|backing track)\b').hasMatch(normalized)) {
      return QueryIntent.karaoke;
    }

    // 10. Album Intent
    if (RegExp(r'\b(album|albums|soundtrack|ost)\b').hasMatch(normalized)) {
      return QueryIntent.album;
    }

    // 11. Playlist Intent
    if (RegExp(r'\b(playlist|top hits|best of|collection)\b').hasMatch(normalized)) {
      return QueryIntent.playlist;
    }

    // 12. Artist Intent Check: Query is an exact known artist name or typo
    for (final artist in _knownArtists) {
      if (normalized == artist) {
        return QueryIntent.artist;
      }
    }

    // Default to Song intent
    return QueryIntent.song;
  }
}
