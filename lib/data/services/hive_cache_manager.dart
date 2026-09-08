import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

/// Hive Cache Manager
/// Handles initialization, storage compaction on startup to prevent fragmentation,
/// and Least Recently Used (LRU) cache eviction once box capacity limits are reached.
class HiveCacheManager {
  static const String boxName = 'search_cache_box';
  static const int maxCapacity = 500;

  /// Initializes the cache box and compacts it to prevent fragmentation.
  static Future<Box> initBox() async {
    // Open the box
    final box = await Hive.openBox(boxName);
    try {
      debugPrint('[HiveCacheManager] 📦 Compacting "$boxName" on startup to prevent storage fragmentation...');
      await box.compact();
      debugPrint('[HiveCacheManager] ✅ Compaction complete. Current cached queries count: ${box.length}');
    } catch (e) {
      debugPrint('[HiveCacheManager] ⚠️ Compaction failed: $e');
    }
    return box;
  }

  /// Evicts the least recently used cache entries if capacity exceeds [maxCapacity].
  /// Assumes cache entries are stored as a JSON/Map structure:
  /// {
  ///   "timestamp": <ms since epoch>,
  ///   "data": <JSON representation of results>
  /// }
  static Future<void> enforceCapacity(Box box) async {
    if (box.length <= maxCapacity) return;

    debugPrint('[HiveCacheManager] ⚠️ Cache capacity exceeded (${box.length}/$maxCapacity). Running LRU Eviction...');

    try {
      final List<MapEntry<dynamic, int>> entriesWithTimestamp = [];

      for (final key in box.keys) {
        final val = box.get(key);
        int timestamp = 0;
        if (val is String) {
          try {
            final decoded = jsonDecode(val);
            if (decoded is Map) {
              timestamp = decoded['timestamp'] as int? ?? 0;
            }
          } catch (_) {}
        } else if (val is Map) {
          timestamp = val['timestamp'] as int? ?? 0;
        }
        entriesWithTimestamp.add(MapEntry(key, timestamp));
      }

      // Sort by timestamp ascending (oldest first)
      entriesWithTimestamp.sort((a, b) => a.value.compareTo(b.value));

      // Calculate how many entries to delete
      final numToDelete = box.length - maxCapacity;
      final keysToDelete = entriesWithTimestamp.take(numToDelete).map((e) => e.key).toList();

      debugPrint('[HiveCacheManager] Pruning $numToDelete oldest entries from search cache.');
      await box.deleteAll(keysToDelete);
      debugPrint('[HiveCacheManager] ✅ LRU Eviction complete. New size: ${box.length}');
    } catch (e) {
      debugPrint('[HiveCacheManager] ❌ LRU Eviction error: $e');
    }
  }
}
