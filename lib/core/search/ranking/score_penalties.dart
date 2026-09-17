import '../models/search_models.dart';

/// Demoting penalties for irrelevant, noisy, or mismatched content
class ScorePenalties {
  /// Computes penalty to subtract from candidate score
  static double calculatePenalty(SearchCandidate candidate, ParsedQuery query) {
    double penalty = 0.0;
    final title = candidate.normalizedTitle;

    // 1. Reaction video penalty (unless explicitly queried for reaction)
    if (candidate.versionType == TrackVersionType.reaction ||
        title.contains('reaction') ||
        title.contains('reacts to')) {
      if (!query.raw.toLowerCase().contains('reaction')) {
        penalty += 0.40;
      }
    }

    // 2. Unrelated Shorts / Clips
    if (candidate.versionType == TrackVersionType.short ||
        title.contains('#shorts') ||
        candidate.duration.inSeconds < 30) {
      penalty += 0.35;
    }

    // 3. Podcasts / Gameplay / Reviews (unless explicitly searched)
    if (candidate.versionType == TrackVersionType.podcast ||
        title.contains('podcast') ||
        title.contains('gameplay') ||
        title.contains('review') ||
        title.contains('trailer') ||
        title.contains('scene')) {
      if (!query.raw.toLowerCase().contains('podcast') &&
          !query.raw.toLowerCase().contains('trailer')) {
        penalty += 0.45;
      }
    }

    // 4. Excessive compilation / Jukebox demotion when searching a specific track
    if ((candidate.versionType == TrackVersionType.compilation ||
            title.contains('jukebox') ||
            title.contains('top bollywood songs') ||
            title.contains('all songs')) &&
        candidate.duration.inSeconds > 1800) {
      if (query.intent == QueryIntent.song && query.entities.title != null) {
        penalty += 0.30;
      }
    }

    // 5. Version mismatch penalty: User wanted acoustic/live/remix, but got unrelated
    if (query.intent == QueryIntent.live &&
        candidate.versionType != TrackVersionType.live) {
      penalty += 0.15;
    } else if (query.intent == QueryIntent.remix &&
        candidate.versionType != TrackVersionType.remix) {
      penalty += 0.15;
    } else if (query.intent == QueryIntent.acoustic &&
        candidate.versionType != TrackVersionType.acoustic) {
      penalty += 0.15;
    } else if (query.intent == QueryIntent.slowed &&
        candidate.versionType != TrackVersionType.slowed) {
      penalty += 0.15;
    }

    return penalty.clamp(0.0, 0.70);
  }
}
