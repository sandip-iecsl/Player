import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/song.dart';

/// Global Firebase Recommendation Engine
/// Connects directly to Firestore to aggregate global listening history,
/// search queries, and track transitions across ALL users of the app.
class GlobalFirebaseEngine {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // We wrap calls in try-catch in case Firebase is not configured yet.
  bool _isFirebaseAvailable = true;

  /// Determines if a song is from local storage (privacy check)
  bool _isLocalSong(Song song) {
    if (song.previewUrl != null && !song.previewUrl!.startsWith('http')) {
      return true; // Local file paths don't start with http
    }
    return false;
  }

  /// Logs that a song was played to the global history.
  Future<void> logPlay(Song song) async {
    if (!_isFirebaseAvailable) return;
    if (_isLocalSong(song)) return; // Privacy: Don't log local files
    
    final connectivity = await Connectivity().checkConnectivity();
    final isOffline = connectivity.contains(ConnectivityResult.none);

    if (isOffline) {
      debugPrint('[Firebase] 📴 Offline. Queuing logPlay for ${song.title}');
      if (Hive.isBoxOpen('firebase_offline_sync_box')) {
        final box = Hive.box('firebase_offline_sync_box');
        box.add(jsonEncode({'type': 'logPlay', 'song': song.toJson()}));
      }
      return;
    }

    try {
      final docRef = _firestore.collection('global_play_history').doc(song.id);
      await docRef.set({
        'title': song.title,
        'artist': song.artist,
        'playCount': FieldValue.increment(1),
        'lastPlayed': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Firebase] ⚠️ Failed to log play. Firebase might not be configured: $e');
      _isFirebaseAvailable = false;
    }
  }

  /// Batch syncs queued offline events to Firestore when network is restored.
  Future<void> syncOfflineQueue() async {
    if (!_isFirebaseAvailable) return;
    if (!Hive.isBoxOpen('firebase_offline_sync_box')) return;
    
    final box = Hive.box('firebase_offline_sync_box');
    if (box.isEmpty) return;

    debugPrint('[Firebase] 🔄 Syncing ${box.length} offline events to Firestore...');
    
    for (int i = 0; i < box.length; i++) {
      try {
        final data = jsonDecode(box.getAt(i) as String);
        if (data['type'] == 'logPlay') {
          final song = Song.fromJson(data['song']);
          await logPlay(song); // Re-run the log method (it will skip offline check since network is restored)
        }
      } catch (e) {
        debugPrint('[Firebase] ❌ Failed to sync offline event at index $i: $e');
      }
    }
    
    await box.clear();
    debugPrint('[Firebase] ✅ Offline sync complete and queue cleared.');
  }

  /// Logs a transition from one song to another.
  /// Document ID is the source song, inside it we store a map of destinations and their counts.
  Future<void> logTransition(Song source, Song dest) async {
    if (!_isFirebaseAvailable) return;
    if (_isLocalSong(source) || _isLocalSong(dest)) return; // Privacy: Don't log local file transitions
    
    try {
      final docRef = _firestore.collection('global_transitions').doc(source.id);
      
      // We use a dot-notation path to increment the specific destination song ID.
      // e.g., transitions.song456 : increment(1)
      await docRef.set({
        'sourceTitle': source.title,
        'transitions': {
          dest.id: FieldValue.increment(1)
        }
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Firebase] ⚠️ Failed to log transition: $e');
    }
  }

  /// Logs a search query to understand global trending searches.
  Future<void> logSearchQuery(String query) async {
    if (!_isFirebaseAvailable) return;
    try {
      final normalizedQuery = query.trim().toLowerCase();
      if (normalizedQuery.isEmpty) return;

      final docRef = _firestore.collection('global_search_history').doc(normalizedQuery);
      await docRef.set({
        'query': query,
        'searchCount': FieldValue.increment(1),
        'lastSearched': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Firebase] ⚠️ Failed to log search: $e');
    }
  }

  /// Fetches the top global transitions for a given seed song.
  /// Returns a map of { destSongId : playCount }
  Future<Map<String, int>> getGlobalTransitions(String seedSongId) async {
    // Disabled to stay within free Firestore read quota
    return {};
  }

  /// Fetches the global play counts (velocity/frequency) for a list of candidate songs.
  Future<Map<String, int>> getGlobalPlayCounts(List<String> songIds) async {
    // Disabled to stay within free Firestore read quota
    return {};
  }
}
