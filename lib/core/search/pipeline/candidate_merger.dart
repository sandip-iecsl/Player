import '../models/search_models.dart';

/// Merges candidate lists and applies Hard Filtering for irrelevant content
class CandidateMerger {
  /// Hard filters out unwanted noise (unrelated podcasts, shorts, reactions, trailers) unless explicitly queried
  static List<SearchCandidate> filterAndMerge(List<SearchCandidate> candidates, ParsedQuery query) {
    if (candidates.isEmpty) return [];

    final rawLower = query.raw.toLowerCase();
    final allowsReactions = rawLower.contains('reaction') || rawLower.contains('react');
    final allowsPodcasts = rawLower.contains('podcast') || rawLower.contains('episode');
    final allowsShorts = rawLower.contains('shorts') || rawLower.contains('short');
    final allowsTrailers = rawLower.contains('trailer') || rawLower.contains('teaser');

    final filtered = <SearchCandidate>[];

    for (final c in candidates) {
      final title = c.normalizedTitle;

      // Filter unwanted reactions
      if (c.versionType == TrackVersionType.reaction && !allowsReactions) {
        continue;
      }
      if (title.contains('reaction') && !allowsReactions) {
        continue;
      }

      // Filter unwanted podcasts
      if (c.versionType == TrackVersionType.podcast && !allowsPodcasts) {
        continue;
      }

      // Filter shorts (< 30s) unless explicit
      if (c.versionType == TrackVersionType.short && !allowsShorts) {
        continue;
      }

      // Filter movie trailers/teasers
      if ((title.contains('official trailer') || title.contains('teaser')) && !allowsTrailers) {
        continue;
      }

      filtered.add(c);
    }

    return filtered;
  }
}
