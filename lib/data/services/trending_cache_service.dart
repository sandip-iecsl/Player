/// A lightweight in-memory TTL cache for trending music data.
///
/// Prevents hammering external APIs on every page load. Each bucket stores its
/// last-fetched timestamp alongside the result. Entries are considered stale
/// after [staleDuration] (default 6 hours) and will be re-fetched on next access.
library trending_cache;

import '../../domain/entities/song.dart';

class TrendingCacheService {
  TrendingCacheService._();
  static final TrendingCacheService instance = TrendingCacheService._();

  static const Duration staleDuration = Duration(hours: 6);

  final Map<String, _CacheBucket<List<Song>>> _buckets = {};

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the cached result for [key] if it exists and is still fresh.
  /// Returns `null` if the cache is empty or stale.
  List<Song>? get(String key) {
    final bucket = _buckets[key];
    if (bucket == null) return null;
    if (_isStale(bucket)) {
      _buckets.remove(key);
      return null;
    }
    return bucket.data;
  }

  /// Stores [data] under [key] with the current timestamp.
  void put(String key, List<Song> data) {
    _buckets[key] = _CacheBucket(data: data, fetchedAt: DateTime.now());
  }

  /// Checks whether a bucket for [key] is present and still fresh.
  bool isFresh(String key) {
    final bucket = _buckets[key];
    if (bucket == null) return false;
    return !_isStale(bucket);
  }

  /// Clears all cached data (e.g., on pull-to-refresh).
  void invalidateAll() => _buckets.clear();

  /// Clears a specific key.
  void invalidate(String key) => _buckets.remove(key);

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool _isStale(_CacheBucket bucket) {
    return DateTime.now().difference(bucket.fetchedAt) > staleDuration;
  }
}

class _CacheBucket<T> {
  final T data;
  final DateTime fetchedAt;
  _CacheBucket({required this.data, required this.fetchedAt});
}
