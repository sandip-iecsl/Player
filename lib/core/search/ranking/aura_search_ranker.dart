import '../models/search_models.dart';
import 'feature_extractor.dart';
import 'score_policy.dart';

/// Aura Search Relevance Ranker
/// Evaluates and ranks candidates using feature extraction, boosts, penalties, and Aura's ranking weights.
class AuraSearchRanker {
  final FeatureExtractor _featureExtractor;
  final ScorePolicy policy;

  AuraSearchRanker({
    FeatureExtractor? featureExtractor,
    this.policy = ScorePolicy.standard,
  }) : _featureExtractor = featureExtractor ?? FeatureExtractor(policy: policy);

  /// Ranks a collection of search candidates against the parsed query
  List<RankedCandidate> rank({
    required List<SearchCandidate> candidates,
    required ParsedQuery query,
  }) {
    if (candidates.isEmpty) return [];

    final rankedList = <RankedCandidate>[];

    for (final candidate in candidates) {
      final features = _featureExtractor.extract(
        candidate: candidate,
        query: query,
      );

      final finalScore = features.computeScore();

      final explanation = 'Text: ${(features.textRelevance * 100).toInt()}% | '
          'Pop: ${(features.popularity * 100).toInt()}% | '
          'Affinity: ${(features.userAffinity * 100).toInt()}% | '
          'Boost: +${(features.exactBoost * 100).toInt()}% | '
          'Pen: -${(features.penalty * 100).toInt()}%';

      rankedList.add(RankedCandidate(
        candidate: candidate,
        finalScore: finalScore,
        features: features,
        rankingExplanation: explanation,
      ));
    }

    // Sort descending by finalScore
    rankedList.sort((a, b) => b.finalScore.compareTo(a.finalScore));

    return rankedList;
  }
}
