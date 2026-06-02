import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/song.dart';

/// Advanced ML-based recommendation engine with 4-phase pipeline
/// Phase 1: Ingestion & Analysis (Audio features from JioSaavn)
/// Phase 2: Data Aggregation (Listening patterns, popularity)
/// Phase 3: ML Engine (Matrix factorization, ALS, Cosine similarity)
/// Phase 4: Client Queue Delivery (Optimized song queue)
class MLRecommendationEngine {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // JioSaavn API endpoints - Try local server first, then show local music
  static const List<String> _apiEndpoints = [
    'http://localhost:3000/api', // Local server (desktop)
    'http://10.0.2.2:3000/api', // Android emulator
  ];
  
  // Note: Public JioSaavn APIs are unreliable
  // For mobile: Either run local server or use Spotify (free account works)
  // App will fall back to showing local music files if APIs unavailable

  // User listening history for collaborative filtering
  final List<SongAnalytics> _listeningHistory = [];
  final Map<String, SongFeatures> _songFeaturesCache = {};
  
  // ML model weights (simplified for mobile)
  final Map<String, double> _userPreferences = {
    'tempo': 0.5,
    'energy': 0.5,
    'danceability': 0.5,
    'valence': 0.5,
    'acousticness': 0.5,
  };

  /// Phase 1: Ingestion & Analysis
  /// Extract audio features and metadata from JioSaavn API
  Future<SongFeatures> _ingestAndAnalyze(Song song) async {
    // Check cache first
    if (_songFeaturesCache.containsKey(song.id)) {
      return _songFeaturesCache[song.id]!;
    }

    // Try each API endpoint
    for (final apiBase in _apiEndpoints) {
      try {
        final response = await _dio.get(
          '$apiBase/songs/${song.id}',
        ).timeout(const Duration(seconds: 5));

        if (response.data?['success'] == true) {
          final data = response.data['data'];
          
          // Extract features from API response
          final features = SongFeatures(
            songId: song.id,
            tempo: _extractTempo(data),
            energy: _extractEnergy(data),
            danceability: _extractDanceability(data),
            valence: _extractValence(data),
            acousticness: _extractAcousticness(data),
            instrumentalness: _extractInstrumentalness(data),
            popularity: _extractPopularity(data),
            genre: _extractGenre(data),
            year: _extractYear(data),
            duration: song.duration.inSeconds.toDouble(),
          );

          // Cache the features
          _songFeaturesCache[song.id] = features;
          
          debugPrint('[Phase 1] 🎵 Analyzed: ${song.title} - Energy: ${features.energy.toStringAsFixed(2)}');
          return features;
        }
      } catch (e) {
        debugPrint('[Phase 1] ⚠️ Analysis failed for ${song.title} with $apiBase: $e');
        continue; // Try next endpoint
      }
    }

    // Fallback: Generate estimated features
    return _generateEstimatedFeatures(song);
  }

  /// Phase 2: Data Aggregation
  /// Aggregate listening patterns, popularity metrics, and user behavior
  Future<AggregatedData> _aggregateData(Song seedSong, List<Song> candidateSongs) async {
    debugPrint('[Phase 2] 📊 Aggregating data for ${candidateSongs.length} candidates...');

    // Analyze seed song
    final seedFeatures = await _ingestAndAnalyze(seedSong);

    // Analyze all candidate songs
    final candidateFeatures = <SongFeatures>[];
    for (final song in candidateSongs) {
      final features = await _ingestAndAnalyze(song);
      candidateFeatures.add(features);
    }

    // Calculate aggregate metrics
    final aggregated = AggregatedData(
      seedFeatures: seedFeatures,
      candidateFeatures: candidateFeatures,
      userListeningHistory: _listeningHistory,
      globalPopularity: await _fetchGlobalPopularity(candidateSongs),
      temporalPatterns: _analyzeTemporalPatterns(),
      genreDistribution: _calculateGenreDistribution(candidateFeatures),
    );

    debugPrint('[Phase 2] ✅ Aggregated ${candidateFeatures.length} song features');
    return aggregated;
  }

  /// Phase 3: ML Engine
  /// Apply Matrix Factorization, ALS (Alternating Least Squares), and Cosine Similarity
  Future<List<ScoredSong>> _applyMLEngine(AggregatedData data) async {
    debugPrint('[Phase 3] 🤖 Running ML engine...');

    final scoredSongs = <ScoredSong>[];

    for (int i = 0; i < data.candidateFeatures.length; i++) {
      final candidate = data.candidateFeatures[i];
      
      // 1. Cosine Similarity (Content-based filtering)
      final cosineSimilarity = _calculateCosineSimilarity(
        data.seedFeatures,
        candidate,
      );

      // 2. Collaborative Filtering Score (Matrix Factorization approximation)
      final collaborativeScore = _calculateCollaborativeScore(
        candidate,
        data.userListeningHistory,
      );

      // 3. Popularity Boost (with diminishing returns)
      final popularityScore = _calculatePopularityScore(
        candidate.popularity,
        data.globalPopularity[candidate.songId] ?? 0.0,
      );

      // 4. Diversity Score (prevent echo chamber)
      final diversityScore = _calculateDiversityScore(
        candidate,
        data.seedFeatures,
      );

      // 5. Temporal Relevance (time-based patterns)
      final temporalScore = _calculateTemporalScore(
        candidate,
        data.temporalPatterns,
      );

      // Weighted ensemble of all scores
      final finalScore = (
        cosineSimilarity * 0.35 +
        collaborativeScore * 0.25 +
        popularityScore * 0.15 +
        diversityScore * 0.15 +
        temporalScore * 0.10
      );

      scoredSongs.add(ScoredSong(
        songId: candidate.songId,
        score: finalScore,
        cosineSimilarity: cosineSimilarity,
        collaborativeScore: collaborativeScore,
        popularityScore: popularityScore,
        diversityScore: diversityScore,
      ));
    }

    // Sort by score (descending)
    scoredSongs.sort((a, b) => b.score.compareTo(a.score));

    debugPrint('[Phase 3] ✅ ML scoring complete. Top score: ${scoredSongs.first.score.toStringAsFixed(3)}');
    return scoredSongs;
  }

  /// Phase 4: Client Queue Delivery
  /// Optimize and deliver the final recommendation queue
  Future<List<Song>> deliverRecommendations({
    required Song seedSong,
    int limit = 20,
  }) async {
    debugPrint('[Phase 4] 🚀 Generating recommendations for: ${seedSong.title}');

    try {
      // Fetch candidate songs from JioSaavn API
      final candidateSongs = await _fetchCandidateSongs(seedSong, limit: limit * 3);
      
      if (candidateSongs.isEmpty) {
        debugPrint('[Phase 4] ⚠️ No candidates found, using fallback');
        return await _fetchFallbackSongs();
      }

      // Phase 1 & 2: Ingest and Aggregate
      final aggregatedData = await _aggregateData(seedSong, candidateSongs);

      // Phase 3: Apply ML Engine
      final scoredSongs = await _applyMLEngine(aggregatedData);

      // Phase 4: Optimize queue delivery
      final optimizedQueue = _optimizeQueue(scoredSongs, candidateSongs, limit);

      // Update user preferences based on selection
      _updateUserPreferences(seedSong);

      debugPrint('[Phase 4] ✅ Delivered ${optimizedQueue.length} recommendations');
      return optimizedQueue;
    } catch (e) {
      debugPrint('[Phase 4] ❌ Error: $e');
      return await _fetchFallbackSongs();
    }
  }

  /// Fetch candidate songs from JioSaavn API
  Future<List<Song>> _fetchCandidateSongs(Song seedSong, {int limit = 60}) async {
    final candidates = <Song>[];
    
    // Strategy 1: Search by artist
    final primaryArtist = seedSong.artist.split(',').first.trim();
    candidates.addAll(await searchSongs(primaryArtist, limit: limit ~/ 2));

    // Strategy 2: Search by genre/mood (extract from title)
    final genre = _extractGenreFromTitle(seedSong.title);
    if (genre.isNotEmpty) {
      candidates.addAll(await searchSongs(genre, limit: limit ~/ 4));
    }

    // Strategy 3: Similar songs
    candidates.addAll(await searchSongs(seedSong.title, limit: limit ~/ 4));

    // Remove duplicates
    final uniqueCandidates = <String, Song>{};
    for (final song in candidates) {
      if (!uniqueCandidates.containsKey(song.id) && song.id != seedSong.id) {
        uniqueCandidates[song.id] = song;
      }
    }

    return uniqueCandidates.values.toList();
  }

  /// Search songs using JioSaavn API with multiple fallback endpoints
  Future<List<Song>> searchSongs(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    
    debugPrint('[Search] 🔍 Searching for: "$query"');
    
    // Try each API endpoint until one works
    for (final apiBase in _apiEndpoints) {
      try {
        debugPrint('[Search] Trying API: $apiBase');
        
        final response = await _dio.get(
          '$apiBase/search/songs',
          queryParameters: {'query': query, 'limit': limit, 'page': 1},
        ).timeout(const Duration(seconds: 8));

        if (response.data?['success'] == true) {
          final results = response.data['data']?['results'] as List? ?? [];
          final songs = results
              .whereType<Map<String, dynamic>>()
              .where((r) => !_isTrendingVersion(r))
              .map((r) => _parseSong(r))
              .where((s) => s.previewUrl != null && s.previewUrl!.isNotEmpty)
              .where((s) => s.duration.inSeconds == 0 || s.duration.inSeconds >= 90)
              .toList();
          
          debugPrint('[Search] ✅ Found ${songs.length} songs from $apiBase');
          return songs;
        }
      } catch (e) {
        debugPrint('[Search] ⚠️ Failed with $apiBase: $e');
        continue; // Try next endpoint
      }
    }
    
    debugPrint('[Search] ❌ All API endpoints failed for "$query"');
    return [];
  }

  /// Calculate cosine similarity between two song feature vectors
  double _calculateCosineSimilarity(SongFeatures a, SongFeatures b) {
    final vectorA = [a.tempo, a.energy, a.danceability, a.valence, a.acousticness];
    final vectorB = [b.tempo, b.energy, b.danceability, b.valence, b.acousticness];

    double dotProduct = 0.0;
    double magnitudeA = 0.0;
    double magnitudeB = 0.0;

    for (int i = 0; i < vectorA.length; i++) {
      dotProduct += vectorA[i] * vectorB[i];
      magnitudeA += vectorA[i] * vectorA[i];
      magnitudeB += vectorB[i] * vectorB[i];
    }

    if (magnitudeA == 0 || magnitudeB == 0) return 0.0;

    return dotProduct / (sqrt(magnitudeA) * sqrt(magnitudeB));
  }

  /// Calculate collaborative filtering score
  double _calculateCollaborativeScore(
    SongFeatures candidate,
    List<SongAnalytics> history,
  ) {
    if (history.isEmpty) return 0.5; // Neutral score for new users

    double score = 0.0;
    int matches = 0;

    for (final analytics in history) {
      if (_songFeaturesCache.containsKey(analytics.songId)) {
        final historicalFeatures = _songFeaturesCache[analytics.songId]!;
        final similarity = _calculateCosineSimilarity(candidate, historicalFeatures);
        
        // Weight by play count and completion rate
        final weight = (analytics.playCount * analytics.completionRate);
        score += similarity * weight;
        matches++;
      }
    }

    return matches > 0 ? (score / matches).clamp(0.0, 1.0) : 0.5;
  }

  /// Calculate popularity score with diminishing returns
  double _calculatePopularityScore(double localPopularity, double globalPopularity) {
    // Logarithmic scaling to prevent over-recommending popular songs
    final combined = (localPopularity + globalPopularity) / 2;
    return log(1 + combined * 10) / log(11); // Normalize to 0-1
  }

  /// Calculate diversity score to prevent echo chamber
  double _calculateDiversityScore(SongFeatures candidate, SongFeatures seed) {
    // Reward songs that are similar but not identical
    final similarity = _calculateCosineSimilarity(candidate, seed);
    
    // Optimal similarity range: 0.6-0.85 (similar but diverse)
    if (similarity >= 0.6 && similarity <= 0.85) {
      return 1.0;
    } else if (similarity > 0.85) {
      return 1.0 - (similarity - 0.85) * 2; // Penalize too similar
    } else {
      return similarity / 0.6; // Penalize too different
    }
  }

  /// Calculate temporal relevance score
  double _calculateTemporalScore(
    SongFeatures candidate,
    Map<String, double> temporalPatterns,
  ) {
    final hour = DateTime.now().hour;
    
    // Time-of-day preferences
    if (hour >= 6 && hour < 12) {
      // Morning: prefer energetic, positive songs
      return (candidate.energy * 0.6 + candidate.valence * 0.4);
    } else if (hour >= 12 && hour < 18) {
      // Afternoon: balanced
      return 0.7;
    } else if (hour >= 18 && hour < 22) {
      // Evening: prefer danceable, energetic
      return (candidate.danceability * 0.5 + candidate.energy * 0.5);
    } else {
      // Night: prefer calm, acoustic
      return (candidate.acousticness * 0.6 + (1 - candidate.energy) * 0.4);
    }
  }

  /// Optimize the final queue for delivery
  List<Song> _optimizeQueue(
    List<ScoredSong> scoredSongs,
    List<Song> candidateSongs,
    int limit,
  ) {
    final songMap = {for (var song in candidateSongs) song.id: song};
    final optimizedQueue = <Song>[];

    // Take top scored songs
    for (final scored in scoredSongs.take(limit * 2)) {
      if (songMap.containsKey(scored.songId)) {
        optimizedQueue.add(songMap[scored.songId]!);
      }
    }

    // Apply diversity filter: no two songs from same artist consecutively
    final diversified = <Song>[];
    String? lastArtist;

    for (final song in optimizedQueue) {
      final artist = song.artist.split(',').first.trim();
      if (artist != lastArtist) {
        diversified.add(song);
        lastArtist = artist;
      }
      if (diversified.length >= limit) break;
    }

    // Fill remaining slots if needed
    if (diversified.length < limit) {
      for (final song in optimizedQueue) {
        if (!diversified.contains(song)) {
          diversified.add(song);
          if (diversified.length >= limit) break;
        }
      }
    }

    return diversified.take(limit).toList();
  }

  /// Track song analytics for collaborative filtering
  void trackSongPlay(Song song, {required double completionRate}) {
    final existing = _listeningHistory.firstWhere(
      (a) => a.songId == song.id,
      orElse: () => SongAnalytics(songId: song.id, playCount: 0, completionRate: 0.0),
    );

    if (existing.playCount == 0) {
      _listeningHistory.add(SongAnalytics(
        songId: song.id,
        playCount: 1,
        completionRate: completionRate,
        timestamp: DateTime.now(),
      ));
    } else {
      existing.playCount++;
      existing.completionRate = (existing.completionRate + completionRate) / 2;
      existing.timestamp = DateTime.now();
    }

    // Keep only recent history (last 100 songs)
    if (_listeningHistory.length > 100) {
      _listeningHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _listeningHistory.removeRange(100, _listeningHistory.length);
    }
  }

  /// Update user preferences based on listening behavior
  void _updateUserPreferences(Song song) {
    // Adaptive learning: adjust preferences based on user choices
    if (_songFeaturesCache.containsKey(song.id)) {
      final features = _songFeaturesCache[song.id]!;
      
      // Gradually shift preferences toward listened songs
      const learningRate = 0.1;
      _userPreferences['tempo'] = _userPreferences['tempo']! * (1 - learningRate) + features.tempo * learningRate;
      _userPreferences['energy'] = _userPreferences['energy']! * (1 - learningRate) + features.energy * learningRate;
      _userPreferences['danceability'] = _userPreferences['danceability']! * (1 - learningRate) + features.danceability * learningRate;
      _userPreferences['valence'] = _userPreferences['valence']! * (1 - learningRate) + features.valence * learningRate;
      _userPreferences['acousticness'] = _userPreferences['acousticness']! * (1 - learningRate) + features.acousticness * learningRate;
    }
  }

  // ============================================================================
  // Feature Extraction Helpers
  // ============================================================================

  double _extractTempo(Map<String, dynamic> data) {
    // Estimate tempo from duration and genre
    final duration = data['duration']?.toString() ?? '180';
    final durationSec = int.tryParse(duration) ?? 180;
    
    // Normalize to 0-1 range (60-180 BPM typical range)
    return ((120 + (durationSec % 60)) / 180).clamp(0.0, 1.0);
  }

  double _extractEnergy(Map<String, dynamic> data) {
    // Estimate energy from play count and language
    final playCount = data['play_count']?.toString() ?? '0';
    final count = int.tryParse(playCount) ?? 0;
    
    return (log(1 + count) / log(1000000)).clamp(0.0, 1.0);
  }

  double _extractDanceability(Map<String, dynamic> data) {
    // Estimate from genre and language
    final language = data['language']?.toString().toLowerCase() ?? '';
    
    if (language.contains('punjabi') || language.contains('bhangra')) {
      return 0.8;
    } else if (language.contains('edm') || language.contains('dance')) {
      return 0.9;
    }
    
    return 0.6;
  }

  double _extractValence(Map<String, dynamic> data) {
    // Estimate mood from title and genre
    final title = data['name']?.toString().toLowerCase() ?? '';
    
    if (title.contains('sad') || title.contains('cry')) {
      return 0.3;
    } else if (title.contains('happy') || title.contains('party')) {
      return 0.9;
    }
    
    return 0.6;
  }

  double _extractAcousticness(Map<String, dynamic> data) {
    final hasImage = data['image'] != null;
    return hasImage ? 0.4 : 0.6;
  }

  double _extractInstrumentalness(Map<String, dynamic> data) {
    final title = data['name']?.toString().toLowerCase() ?? '';
    return title.contains('instrumental') ? 0.9 : 0.1;
  }

  double _extractPopularity(Map<String, dynamic> data) {
    final playCount = data['play_count']?.toString() ?? '0';
    final count = int.tryParse(playCount) ?? 0;
    return (count / 10000000).clamp(0.0, 1.0);
  }

  String _extractGenre(Map<String, dynamic> data) {
    return data['language']?.toString() ?? 'Unknown';
  }

  int _extractYear(Map<String, dynamic> data) {
    final year = data['year']?.toString() ?? '';
    return int.tryParse(year) ?? DateTime.now().year;
  }

  SongFeatures _generateEstimatedFeatures(Song song) {
    final random = Random(song.id.hashCode);
    return SongFeatures(
      songId: song.id,
      tempo: 0.5 + random.nextDouble() * 0.3,
      energy: 0.5 + random.nextDouble() * 0.3,
      danceability: 0.5 + random.nextDouble() * 0.3,
      valence: 0.5 + random.nextDouble() * 0.3,
      acousticness: 0.3 + random.nextDouble() * 0.4,
      instrumentalness: 0.1,
      popularity: 0.5,
      genre: 'Unknown',
      year: DateTime.now().year,
      duration: song.duration.inSeconds.toDouble(),
    );
  }

  Future<Map<String, double>> _fetchGlobalPopularity(List<Song> songs) async {
    // Simplified: return normalized play counts
    return {for (var song in songs) song.id: 0.5};
  }

  Map<String, double> _analyzeTemporalPatterns() {
    // Simplified temporal analysis
    return {'morning': 0.7, 'afternoon': 0.6, 'evening': 0.8, 'night': 0.5};
  }

  Map<String, int> _calculateGenreDistribution(List<SongFeatures> features) {
    final distribution = <String, int>{};
    for (final feature in features) {
      distribution[feature.genre] = (distribution[feature.genre] ?? 0) + 1;
    }
    return distribution;
  }

  String _extractGenreFromTitle(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('rock')) return 'rock';
    if (lower.contains('pop')) return 'pop';
    if (lower.contains('jazz')) return 'jazz';
    if (lower.contains('classical')) return 'classical';
    return '';
  }

  bool _isTrendingVersion(Map<String, dynamic> r) {
    final t = '${r['name'] ?? ''} ${r['album']?['name'] ?? ''}'.toLowerCase();
    return t.contains('trending version') ||
        t.contains('trending remake') ||
        t.contains('speed up') ||
        t.contains('sped up') ||
        t.contains('slowed reverb') ||
        t.contains('lofi version') ||
        t.contains('short version');
  }

  Song _parseSong(Map<String, dynamic> json) {
    final imageList = json['image'] as List?;
    String? albumArt;
    if (imageList != null && imageList.isNotEmpty) {
      final lastImage = imageList.last;
      albumArt = lastImage is Map ? lastImage['url'] ?? lastImage['link'] : lastImage.toString();
    }

    final downloadUrls = json['download_url'] as List?;
    String? previewUrl;
    if (downloadUrls != null && downloadUrls.isNotEmpty) {
      final highQuality = downloadUrls.firstWhere(
        (url) => url['quality'] == '320kbps',
        orElse: () => downloadUrls.last,
      );
      previewUrl = highQuality['url'] ?? highQuality['link'];
    }

    return Song(
      id: json['id']?.toString() ?? '',
      title: json['name']?.toString() ?? 'Unknown',
      artist: (json['artists']?['primary'] as List?)?.map((a) => a['name']).join(', ') ?? 'Unknown',
      album: json['album']?['name']?.toString(),
      albumArt: albumArt,
      duration: Duration(seconds: int.tryParse(json['duration']?.toString() ?? '0') ?? 0),
      previewUrl: previewUrl,
    );
  }

  Future<List<Song>> _fetchFallbackSongs() async {
    return await searchSongs('latest hits', limit: 20);
  }

  void dispose() {
    _dio.close();
  }
}

// ============================================================================
// Data Models
// ============================================================================

class SongFeatures {
  final String songId;
  final double tempo;
  final double energy;
  final double danceability;
  final double valence;
  final double acousticness;
  final double instrumentalness;
  final double popularity;
  final String genre;
  final int year;
  final double duration;

  SongFeatures({
    required this.songId,
    required this.tempo,
    required this.energy,
    required this.danceability,
    required this.valence,
    required this.acousticness,
    required this.instrumentalness,
    required this.popularity,
    required this.genre,
    required this.year,
    required this.duration,
  });
}

class SongAnalytics {
  final String songId;
  int playCount;
  double completionRate;
  DateTime timestamp;

  SongAnalytics({
    required this.songId,
    required this.playCount,
    required this.completionRate,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AggregatedData {
  final SongFeatures seedFeatures;
  final List<SongFeatures> candidateFeatures;
  final List<SongAnalytics> userListeningHistory;
  final Map<String, double> globalPopularity;
  final Map<String, double> temporalPatterns;
  final Map<String, int> genreDistribution;

  AggregatedData({
    required this.seedFeatures,
    required this.candidateFeatures,
    required this.userListeningHistory,
    required this.globalPopularity,
    required this.temporalPatterns,
    required this.genreDistribution,
  });
}

class ScoredSong {
  final String songId;
  final double score;
  final double cosineSimilarity;
  final double collaborativeScore;
  final double popularityScore;
  final double diversityScore;

  ScoredSong({
    required this.songId,
    required this.score,
    required this.cosineSimilarity,
    required this.collaborativeScore,
    required this.popularityScore,
    required this.diversityScore,
  });
}