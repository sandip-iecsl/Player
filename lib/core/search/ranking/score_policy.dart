/// Configurable weights and thresholds for the Aura Ranking Engine
class ScorePolicy {
  // Ranking formula weights (Sum = 1.00)
  final double textRelevanceWeight;
  final double popularityWeight;
  final double userAffinityWeight;
  final double freshnessWeight;
  final double trendWeight;
  final double intentMatchWeight;
  final double languageMatchWeight;
  final double versionMatchWeight;

  // Text relevance sub-weights
  final double exactTitleWeight;
  final double titleSimilarityWeight;
  final double artistMatchWeight;
  final double tokenMatchWeight;
  final double fuzzyMatchWeight;
  final double albumMatchWeight;

  const ScorePolicy({
    this.textRelevanceWeight = 0.42,
    this.popularityWeight = 0.14,
    this.userAffinityWeight = 0.15,
    this.freshnessWeight = 0.08,
    this.trendWeight = 0.07,
    this.intentMatchWeight = 0.06,
    this.languageMatchWeight = 0.04,
    this.versionMatchWeight = 0.04,
    this.exactTitleWeight = 0.35,
    this.titleSimilarityWeight = 0.20,
    this.artistMatchWeight = 0.15,
    this.tokenMatchWeight = 0.10,
    this.fuzzyMatchWeight = 0.10,
    this.albumMatchWeight = 0.05,
  });

  static const ScorePolicy standard = ScorePolicy();
}
