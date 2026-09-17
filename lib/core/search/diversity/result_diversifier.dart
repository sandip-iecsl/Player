import '../models/search_models.dart';

/// Result Diversifier: Prevents result clustering by artist or track version
class ResultDiversifier {
  final int maxPerArtist;
  final int maxPerVersion;

  const ResultDiversifier({
    this.maxPerArtist = 4,
    this.maxPerVersion = 3,
  });

  /// Diversifies ranked results to create a rich and balanced search result page
  List<RankedCandidate> diversify({
    required List<RankedCandidate> rankedResults,
    required ParsedQuery query,
  }) {
    if (rankedResults.length <= 3) return rankedResults;

    // If user explicitly searched for a specific artist or version, relax diversity limits
    final isArtistQuery = query.intent == QueryIntent.artist;
    final isVersionQuery = query.entities.version != null ||
        query.intent == QueryIntent.live ||
        query.intent == QueryIntent.remix ||
        query.intent == QueryIntent.acoustic;

    final artistLimit = isArtistQuery ? 15 : maxPerArtist;
    final versionLimit = isVersionQuery ? 15 : maxPerVersion;

    final accepted = <RankedCandidate>[];
    final deferred = <RankedCandidate>[];

    final artistCounts = <String, int>{};
    final versionCounts = <String, int>{};

    for (int i = 0; i < rankedResults.length; i++) {
      final item = rankedResults[i];
      final artist = item.candidate.normalizedArtist;
      final versionKey = '${item.candidate.normalizedTitle}_${item.candidate.versionType.name}';

      final currentArtistCount = artistCounts[artist] ?? 0;
      final currentVersionCount = versionCounts[versionKey] ?? 0;

      // Always keep the top #1 result regardless of limits
      if (i == 0 || (currentArtistCount < artistLimit && currentVersionCount < versionLimit)) {
        accepted.add(item);
        artistCounts[artist] = currentArtistCount + 1;
        versionCounts[versionKey] = currentVersionCount + 1;
      } else {
        deferred.add(item);
      }
    }

    // Append deferred results at the end if accepted count is below request limit
    return [...accepted, ...deferred];
  }
}
