import '../models/search_models.dart';
import 'canonical_track_resolver.dart';

/// Deduplicator for multi-provider search candidate streams
class SearchDeduplicator {
  /// Deduplicates and merges candidate tracks from multiple providers
  static List<SearchCandidate> deduplicate(List<SearchCandidate> candidates) {
    if (candidates.isEmpty) return [];

    final result = <SearchCandidate>[];

    for (final candidate in candidates) {
      int matchIndex = -1;

      for (int i = 0; i < result.length; i++) {
        if (CanonicalTrackResolver.areSameTrack(result[i], candidate)) {
          matchIndex = i;
          break;
        }
      }

      if (matchIndex >= 0) {
        // Merge with existing canonical object
        final existing = result[matchIndex];
        result[matchIndex] = CanonicalTrackResolver.mergeCandidates(existing, candidate);
      } else {
        result.add(candidate);
      }
    }

    return result;
  }
}
