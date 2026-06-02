import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/song.dart';
import 'ml_recommendation_engine.dart';
import 'queue_manager.dart';

/// JioSaavn Adapter - Adapts JioSaavn/ML Engine to work with QueueManager
/// This allows JioSaavn to use the same queue management as Spotify
class JioSaavnAdapter {
  final MLRecommendationEngine _mlEngine;

  JioSaavnAdapter(this._mlEngine);

  /// Search and generate queue (mimics Spotify's searchAndGenerateQueue)
  Future<JioSaavnPlaybackResult> searchAndGenerateQueue({
    required String query,
    int recommendationLimit = 20,
  }) async {
    debugPrint('[JioSaavn Adapter] 🔍 Searching: "$query"');

    // Search for target track
    final searchResults = await _mlEngine.searchSongs(query, limit: 1);
    if (searchResults.isEmpty) {
      throw Exception('No tracks found for query: $query');
    }

    final targetTrack = searchResults.first;
    debugPrint('[JioSaavn Adapter] 🎵 Found: ${targetTrack.title}');

    // Generate ML-based recommendations
    final recommendations = await _mlEngine.deliverRecommendations(
      seedSong: targetTrack,
      limit: recommendationLimit,
    );

    final List<Song> queue = [targetTrack, ...recommendations];
    
    debugPrint('[JioSaavn Adapter] ✅ Generated queue: ${queue.length} tracks');

    return JioSaavnPlaybackResult(
      targetTrack: targetTrack,
      queue: queue,
      currentIndex: 0,
    );
  }

  /// Get recommendations (mimics Spotify's _getRecommendations)
  Future<List<Song>> getRecommendations({
    required String seedTrackId,
    int limit = 20,
  }) async {
    // Find the seed song first
    final searchResults = await _mlEngine.searchSongs(seedTrackId, limit: 1);
    if (searchResults.isEmpty) {
      return [];
    }

    final seedSong = searchResults.first;
    return await _mlEngine.deliverRecommendations(
      seedSong: seedSong,
      limit: limit,
    );
  }

  void dispose() {
    _mlEngine.dispose();
  }
}

/// Result from JioSaavn search and queue generation
class JioSaavnPlaybackResult {
  final Song targetTrack;
  final List<Song> queue;
  final int currentIndex;

  JioSaavnPlaybackResult({
    required this.targetTrack,
    required this.queue,
    required this.currentIndex,
  });
}
