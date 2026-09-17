import '../models/search_models.dart';

/// Exact match and positive contextual score boosts
class ScoreBoosts {
  /// Computes additive boost for candidate relative to parsed query
  static double calculateBoost(SearchCandidate candidate, ParsedQuery query) {
    double boost = 0.0;
    final qTitle = query.entities.title?.toLowerCase().trim() ?? '';
    final qArtist = query.entities.artist?.toLowerCase().trim() ?? '';
    final rawClean = query.effectiveQuery.toLowerCase().trim();

    final cTitle = candidate.normalizedTitle;
    final cArtist = candidate.normalizedArtist;

    // 1. Exact Title Match
    if (cTitle == rawClean || (qTitle.isNotEmpty && cTitle == qTitle)) {
      boost += 0.25;
    } else if (cTitle.startsWith(rawClean) || (qTitle.isNotEmpty && cTitle.startsWith(qTitle))) {
      boost += 0.15;
    }

    // 2. Exact Artist Match
    if (cArtist == rawClean || (qArtist.isNotEmpty && cArtist == qArtist)) {
      boost += 0.15;
    }

    // 3. Exact Full Phrase ("Title - Artist" or "Artist - Title")
    final fullCandidate = '$cTitle $cArtist';
    if (fullCandidate.contains(rawClean) || rawClean.contains(cTitle)) {
      boost += 0.10;
    }

    // 4. Official Audio / Video Content Boost
    if (candidate.versionType == TrackVersionType.official ||
        candidate.versionType == TrackVersionType.officialAudio ||
        candidate.versionType == TrackVersionType.musicVideo) {
      boost += 0.08;
    }

    // 5. Version modifier boost when requested
    if (query.entities.version != null && query.entities.version == candidate.versionType) {
      boost += 0.20;
    }

    // 6. Live boost if intent is live
    if (query.intent == QueryIntent.live && candidate.versionType == TrackVersionType.live) {
      boost += 0.25;
    }

    // 7. Remix boost if intent is remix
    if (query.intent == QueryIntent.remix && candidate.versionType == TrackVersionType.remix) {
      boost += 0.25;
    }

    // 8. Acoustic boost if intent is acoustic
    if (query.intent == QueryIntent.acoustic && candidate.versionType == TrackVersionType.acoustic) {
      boost += 0.25;
    }

    // 9. Slowed / Lofi boost if intent is slowed / lofi
    if ((query.intent == QueryIntent.slowed && candidate.versionType == TrackVersionType.slowed) ||
        (query.intent == QueryIntent.lofi && candidate.versionType == TrackVersionType.lofi)) {
      boost += 0.25;
    }

    return boost.clamp(0.0, 0.40);
  }
}
