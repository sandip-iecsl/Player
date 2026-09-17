import 'dart:math';
import '../models/search_models.dart';
import '../ranking/string_similarity.dart';

/// Canonical Track Resolver
/// Resolves cross-provider track identity using ISRC, MusicBrainz ID, and normalized title+artist+duration
class CanonicalTrackResolver {
  /// Checks whether two candidates represent the exact same musical track
  static bool areSameTrack(SearchCandidate a, SearchCandidate b) {
    // 1. ISRC Match (Highest Confidence)
    if (a.isrc != null && b.isrc != null && a.isrc!.isNotEmpty && b.isrc!.isNotEmpty) {
      if (a.isrc!.toUpperCase().trim() == b.isrc!.toUpperCase().trim()) {
        return true;
      }
    }

    // 2. MusicBrainz ID Match
    if (a.musicBrainzId != null && b.musicBrainzId != null &&
        a.musicBrainzId!.isNotEmpty && b.musicBrainzId!.isNotEmpty) {
      if (a.musicBrainzId == b.musicBrainzId) {
        return true;
      }
    }

    // 3. Check Artist Equality / High Similarity First (Do NOT merge different artists!)
    final artistSim = StringSimilarity.levenshteinSimilarity(a.normalizedArtist, b.normalizedArtist);
    final isSameArtist = a.normalizedArtist == b.normalizedArtist ||
        a.normalizedArtist.contains(b.normalizedArtist) ||
        b.normalizedArtist.contains(a.normalizedArtist) ||
        artistSim >= 0.80;

    if (!isSameArtist) {
      return false; // Different artists -> Never merge!
    }

    // 4. Check Title Similarity
    final titleSim = StringSimilarity.levenshteinSimilarity(a.normalizedTitle, b.normalizedTitle);
    final isSameTitle = a.normalizedTitle == b.normalizedTitle ||
        titleSim >= 0.85;

    if (!isSameTitle) {
      return false;
    }

    // 5. Check Duration Bucket (Tolerance of +/- 12 seconds)
    final durationDiff = (a.duration.inSeconds - b.duration.inSeconds).abs();
    if (durationDiff <= 12) {
      return true;
    }

    // If version types match and title is identical
    if (a.normalizedTitle == b.normalizedTitle && a.versionType == b.versionType && durationDiff <= 25) {
      return true;
    }

    return false;
  }

  /// Merges two candidate tracks into a single canonical representation, preserving all IDs
  static SearchCandidate mergeCandidates(SearchCandidate primary, SearchCandidate secondary) {
    final matchedProviders = <SearchProviderType>{
      ...primary.matchedProviders,
      ...secondary.matchedProviders,
      primary.sourceProvider,
      secondary.sourceProvider,
    }.toList();

    return primary.copyWith(
      youtubeId: primary.youtubeId ?? secondary.youtubeId,
      audiusId: primary.audiusId ?? secondary.audiusId,
      jamendoId: primary.jamendoId ?? secondary.jamendoId,
      jioSaavnId: primary.jioSaavnId ?? secondary.jioSaavnId,
      spotifyId: primary.spotifyId ?? secondary.spotifyId,
      deezerId: primary.deezerId ?? secondary.deezerId,
      isrc: primary.isrc ?? secondary.isrc,
      musicBrainzId: primary.musicBrainzId ?? secondary.musicBrainzId,
      artworkUrl: primary.artworkUrl ?? secondary.artworkUrl,
      playableUrl: primary.playableUrl ?? secondary.playableUrl,
      previewUrl: primary.previewUrl ?? secondary.previewUrl,
      isDownloadable: primary.isDownloadable || secondary.isDownloadable,
      viewCount: max(primary.viewCount ?? 0, secondary.viewCount ?? 0),
      likeCount: max(primary.likeCount ?? 0, secondary.likeCount ?? 0),
      popularityScore: max(primary.popularityScore ?? 0.0, secondary.popularityScore ?? 0.0),
      matchedProviders: matchedProviders,
    );
  }
}
