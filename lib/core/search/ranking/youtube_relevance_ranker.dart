import 'dart:math';
import '../../../data/models/song_model.dart';
import 'string_similarity.dart';

/// Multi-Factor YouTube-Style Relevance and Play Velocity Ranking Engine
/// 
/// Formula:
/// Final Score = (Text Similarity * 0.4) + (Global Play Velocity * 0.3) + (User Taste Affinity * 0.2) + (Market Trend Boost * 0.1)
class YouTubeRelevanceRanker {
  final double textSimilarityWeight;
  final double playVelocityWeight;
  final double userTasteWeight;
  final double marketTrendWeight;

  const YouTubeRelevanceRanker({
    this.textSimilarityWeight = 0.40,
    this.playVelocityWeight = 0.30,
    this.userTasteWeight = 0.20,
    this.marketTrendWeight = 0.10,
  });

  /// Ranks candidates based on the multi-factor YouTube formula
  List<SongModel> rank({
    required String query,
    required List<SongModel> candidates,
    Map<String, double>? globalPlayVelocityMap, // SongId -> [0.0 - 1.0]
    Set<String>? userFavoriteArtists, // Artists user listens to frequently
    Set<String>? trendingSongIds, // Top charted track IDs
  }) {
    if (candidates.isEmpty) return [];

    final cleanQuery = query.trim().toLowerCase();
    final scoredList = <_ScoredCandidate>[];

    for (final song in candidates) {
      // 1. Text Similarity (Title & Artist)
      final titleSim = StringSimilarity.fuzzyScore(cleanQuery, song.title);
      final artistSim = StringSimilarity.fuzzyScore(cleanQuery, song.artist);
      final textScore = max(titleSim, artistSim * 0.85);

      // 2. Global Play Velocity [0.0 - 1.0]
      final velocity = globalPlayVelocityMap?[song.id] ?? 0.35;

      // 3. User Taste Affinity [0.0 - 1.0]
      double tasteAffinity = 0.10;
      if (userFavoriteArtists != null && userFavoriteArtists.contains(song.artist.toLowerCase())) {
        tasteAffinity = 1.0;
      }

      // 4. Market Trend Boost [0.0 - 1.0]
      final bool isTrending = trendingSongIds?.contains(song.id) ?? false;
      final double trendBoost = isTrending ? 1.0 : 0.20;

      // Composite Multi-Factor Score Calculation
      final finalScore = (textScore * textSimilarityWeight) +
          (velocity * playVelocityWeight) +
          (tasteAffinity * userTasteWeight) +
          (trendBoost * marketTrendWeight);

      scoredList.add(_ScoredCandidate(song: song, score: finalScore));
    }

    // Sort descending by calculated score
    scoredList.sort((a, b) => b.score.compareTo(a.score));

    return scoredList.map((e) => e.song).toList();
  }
}

class _ScoredCandidate {
  final SongModel song;
  final double score;

  const _ScoredCandidate({required this.song, required this.score});
}
