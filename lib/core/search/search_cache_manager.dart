import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../data/models/song_model.dart';
import 'search_engine_provider.dart';
import 'search_tier.dart';

/// Manages client-side persistent caching for search queries in Hive (`search_cache_box`).
/// Provides 0ms latency and 0 cloud cost on cache hits.
class SearchCacheManager {
  static const String boxName = 'search_cache_box';
  static const int maxCacheEntries = 500;
  static const Duration defaultTtl = Duration(hours: 24);

  Box? _box;

  SearchCacheManager([this._box]);

  /// Opens or retrieves the Hive cache box
  Future<Box?> _getBox() async {
    try {
      if (_box != null && _box!.isOpen) return _box!;
      if (Hive.isBoxOpen(boxName)) {
        _box = Hive.box(boxName);
        return _box!;
      }
      _box = await Hive.openBox(boxName);
      return _box!;
    } catch (e) {
      debugPrint('[SearchCache] Hive box unavailable: $e');
      return null;
    }
  }

  /// Normalizes a query string for deterministic cache keying
  String normalizeKey(String query) {
    return query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Checks if cached results exist for the query and are not expired
  Future<SearchResultPayload?> getCachedResults(String query, {Duration? maxAge}) async {
    final key = normalizeKey(query);
    if (key.isEmpty) return null;

    try {
      final box = await _getBox();
      if (box == null || !box.containsKey(key)) return null;

      final dynamic raw = box.get(key);
      if (raw == null) return null;

      Map<String, dynamic> data;
      int timestamp = 0;

      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          if (decoded.containsKey('data') && decoded.containsKey('timestamp')) {
            data = Map<String, dynamic>.from(decoded['data'] as Map);
            timestamp = decoded['timestamp'] as int? ?? 0;
          } else {
            data = decoded;
            timestamp = DateTime.now().millisecondsSinceEpoch;
          }
        } else {
          return null;
        }
      } else if (raw is Map) {
        data = Map<String, dynamic>.from(raw);
        timestamp = data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
      } else {
        return null;
      }

      // Check TTL expiration
      final ttl = maxAge ?? defaultTtl;
      final entryAge = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (entryAge > ttl.inMilliseconds) {
        debugPrint('[SearchCache] Expired entry for "$key" (${entryAge}ms old). Evicting.');
        await box.delete(key);
        return null;
      }

      // Parse cached songs
      final songsList = (data['songs'] as List?) ?? [];
      final parsedSongs = <SongModel>[];
      for (final s in songsList) {
        if (s is Map) {
          try {
            parsedSongs.add(SongModel.fromJson(Map<String, dynamic>.from(s)));
          } catch (_) {}
        }
      }

      if (parsedSongs.isEmpty) return null;

      debugPrint('[SearchCache] ⚡ Cache HIT for "$key" (Found ${parsedSongs.length} songs, 0ms latency)');

      // Update LRU access timestamp
      final updatedWrap = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': data,
      };
      await box.put(key, jsonEncode(updatedWrap));

      return SearchResultPayload(
        songs: parsedSongs,
        tier: SearchTier.cache,
        providerName: 'Local Hive Cache (0ms)',
        latency: Duration.zero,
        isFromCache: true,
        query: query,
      );
    } catch (e) {
      debugPrint('[SearchCache] Error reading cache for "$key": $e');
      return null;
    }
  }

  /// Stores successful search results into Hive cache box
  Future<void> cacheResults(String query, List<SongModel> songs) async {
    final key = normalizeKey(query);
    if (key.isEmpty || songs.isEmpty) return;

    try {
      final box = await _getBox();
      if (box == null) return;

      // Enforce max entry capacity with LRU eviction
      if (box.length >= maxCacheEntries) {
        final oldestKey = box.keys.first;
        await box.delete(oldestKey);
      }

      final payload = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': {
          'songs': songs.map((s) => s.toJson()).toList(),
        },
      };

      await box.put(key, jsonEncode(payload));
      debugPrint('[SearchCache] 💾 Cached ${songs.length} songs for key "$key"');
    } catch (e) {
      debugPrint('[SearchCache] Error saving cache for "$key": $e');
    }
  }

  /// Clears all cached search queries
  Future<void> clearCache() async {
    try {
      final box = await _getBox();
      if (box == null) return;
      await box.clear();
      debugPrint('[SearchCache] 🧹 Cache cleared completely');
    } catch (e) {
      debugPrint('[SearchCache] Error clearing cache: $e');
    }
  }
}
