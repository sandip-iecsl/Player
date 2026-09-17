import 'dart:math';
import '../../../data/services/local_taste_engine.dart';
import '../models/search_models.dart';
import 'score_boosts.dart';
import 'score_penalties.dart';
import 'score_policy.dart';
import 'string_similarity.dart';

/// Feature Extractor for computing the ranking feature vector of a SearchCandidate
class FeatureExtractor {
  final ScorePolicy policy;
  final LocalTasteEngine _tasteEngine;

  FeatureExtractor({
    this.policy = ScorePolicy.standard,
    LocalTasteEngine? tasteEngine,
  }) : _tasteEngine = tasteEngine ?? LocalTasteEngine();

  /// Extracts full RankingFeatures vector
  RankingFeatures extract({
    required SearchCandidate candidate,
    required ParsedQuery query,
  }) {
    final textRel = _computeTextRelevance(candidate, query);
    final pop = _computePopularity(candidate);
    final affinity = _computeUserAffinity(candidate);
    final fresh = _computeFreshness(candidate);
    final trend = _computeTrend(candidate);
    final intentM = _computeIntentMatch(candidate, query);
    final langM = _computeLanguageMatch(candidate, query);
    final verM = _computeVersionMatch(candidate, query);
    final boost = ScoreBoosts.calculateBoost(candidate, query);
    final pen = ScorePenalties.calculatePenalty(candidate, query);

    return RankingFeatures(
      textRelevance: textRel,
      popularity: pop,
      userAffinity: affinity,
      freshness: fresh,
      trend: trend,
      intentMatch: intentM,
      languageMatch: langM,
      versionMatch: verM,
      exactBoost: boost,
      penalty: pen,
    );
  }

  double _computeTextRelevance(SearchCandidate candidate, ParsedQuery query) {
    final effectiveQ = query.effectiveQuery.toLowerCase().trim();
    final cTitle = candidate.normalizedTitle;
    final cArtist = candidate.normalizedArtist;
    final cAlbum = candidate.normalizedAlbum ?? '';

    // 1. Exact Title match
    double exactTitleScore = 0.0;
    if (cTitle == effectiveQ) {
      exactTitleScore = 1.0;
    } else if (cTitle.startsWith(effectiveQ)) {
      exactTitleScore = 0.85;
    } else if (cTitle.contains(effectiveQ)) {
      exactTitleScore = 0.70;
    }

    // 2. Title similarity (Levenshtein + Jaro-Winkler)
    final titleSim = StringSimilarity.fuzzyScore(effectiveQ, cTitle);

    // 3. Artist match
    double artistScore = 0.0;
    if (query.entities.artist != null) {
      final qArtist = query.entities.artist!.toLowerCase().trim();
      if (cArtist == qArtist) {
        artistScore = 1.0;
      } else if (cArtist.contains(qArtist) || qArtist.contains(cArtist)) {
        artistScore = 0.80;
      } else {
        artistScore = StringSimilarity.levenshteinSimilarity(qArtist, cArtist);
      }
    } else {
      if (cArtist.contains(effectiveQ) || effectiveQ.contains(cArtist)) {
        artistScore = 0.75;
      } else {
        artistScore = StringSimilarity.levenshteinSimilarity(effectiveQ, cArtist);
      }
    }

    // 4. Token Overlap
    final fullCandidateText = '$cTitle $cArtist $cAlbum';
    final tokenScore = StringSimilarity.tokenOverlapScore(effectiveQ, fullCandidateText);

    // 5. Fuzzy / N-Gram match
    final fuzzyScore = StringSimilarity.nGramSimilarity(effectiveQ, fullCandidateText);

    // 6. Album match
    double albumScore = 0.0;
    if (cAlbum.isNotEmpty) {
      if (effectiveQ.contains(cAlbum) || cAlbum.contains(effectiveQ)) {
        albumScore = 0.80;
      } else {
        albumScore = StringSimilarity.levenshteinSimilarity(effectiveQ, cAlbum);
      }
    }

    // Weighted combination of text relevance
    final compositeText = (exactTitleScore * policy.exactTitleWeight) +
        (titleSim * policy.titleSimilarityWeight) +
        (artistScore * policy.artistMatchWeight) +
        (tokenScore * policy.tokenMatchWeight) +
        (fuzzyScore * policy.fuzzyMatchWeight) +
        (albumScore * policy.albumMatchWeight);

    return compositeText.clamp(0.0, 1.0);
  }

  double _computePopularity(SearchCandidate candidate) {
    if (candidate.popularityScore != null) {
      return candidate.popularityScore!.clamp(0.0, 1.0);
    }
    if (candidate.viewCount != null && candidate.viewCount! > 0) {
      // Log10 scaling: 1k -> 0.3, 10k -> 0.4, 100k -> 0.5, 1M -> 0.6, 10M -> 0.7, 100M -> 0.8, 1B -> 0.9
      final logVal = (log(candidate.viewCount!) / ln10) / 10.0;
      return logVal.clamp(0.05, 1.0);
    }
    return 0.40; // Neutral default
  }

  double _computeUserAffinity(SearchCandidate candidate) {
    try {
      final song = candidate.toSong();
      final affinity = _tasteEngine.getAffinityScore(song, song);
      // Normalize raw affinity score (max scale around 15.0)
      return (affinity / 15.0).clamp(0.0, 1.0);
    } catch (_) {
      return 0.1;
    }
  }

  double _computeFreshness(SearchCandidate candidate) {
    if (candidate.publishedAt == null) return 0.5;

    final ageInDays = DateTime.now().difference(candidate.publishedAt!).inDays;
    if (ageInDays <= 0) return 1.0;

    // Exponential decay with half-life of ~180 days for music
    final decay = exp(-0.693 * ageInDays / 180.0);
    return decay.clamp(0.05, 1.0);
  }

  double _computeTrend(SearchCandidate candidate) {
    // If viewCount and likeCount available, calculate like ratio velocity
    if (candidate.viewCount != null && candidate.likeCount != null && candidate.viewCount! > 0) {
      final ratio = candidate.likeCount! / candidate.viewCount!;
      return (ratio * 10.0).clamp(0.1, 1.0);
    }
    return 0.50;
  }

  double _computeIntentMatch(SearchCandidate candidate, ParsedQuery query) {
    switch (query.intent) {
      case QueryIntent.song:
        return (candidate.versionType == TrackVersionType.official ||
                candidate.versionType == TrackVersionType.officialAudio ||
                candidate.versionType == TrackVersionType.musicVideo)
            ? 1.0
            : 0.6;
      case QueryIntent.artist:
        return query.effectiveQuery == candidate.normalizedArtist ? 1.0 : 0.7;
      case QueryIntent.album:
        return (candidate.album != null && candidate.normalizedAlbum == query.effectiveQuery) ? 1.0 : 0.6;
      case QueryIntent.live:
        return candidate.versionType == TrackVersionType.live ? 1.0 : 0.2;
      case QueryIntent.remix:
        return candidate.versionType == TrackVersionType.remix ? 1.0 : 0.2;
      case QueryIntent.acoustic:
        return candidate.versionType == TrackVersionType.acoustic ? 1.0 : 0.2;
      case QueryIntent.slowed:
        return candidate.versionType == TrackVersionType.slowed ? 1.0 : 0.2;
      case QueryIntent.lofi:
        return candidate.versionType == TrackVersionType.lofi ? 1.0 : 0.2;
      case QueryIntent.cover:
        return candidate.versionType == TrackVersionType.cover ? 1.0 : 0.3;
      case QueryIntent.lyrics:
        return candidate.versionType == TrackVersionType.lyrics ? 1.0 : 0.5;
      default:
        return 0.7;
    }
  }

  double _computeLanguageMatch(SearchCandidate candidate, ParsedQuery query) {
    if (query.detectedLanguage == null || candidate.language == null) return 0.8;
    return query.detectedLanguage!.toLowerCase() == candidate.language!.toLowerCase() ? 1.0 : 0.4;
  }

  double _computeVersionMatch(SearchCandidate candidate, ParsedQuery query) {
    if (query.entities.version == null) return 0.8;
    return query.entities.version == candidate.versionType ? 1.0 : 0.3;
  }
}
