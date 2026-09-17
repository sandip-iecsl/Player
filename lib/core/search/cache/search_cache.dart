import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/search_models.dart';
import 'search_cache_key.dart';

/// Hive-backed LRU & TTL Search Cache Manager
class SearchCache {
  static const String boxName = 'aura_search_cache_v2';
  static const int maxCacheEntries = 200;
  static const Duration defaultTtl = Duration(hours: 24);

  int _hits = 0;
  int _misses = 0;

  int get hits => _hits;
  int get misses => _misses;
  double get hitRate => (_hits + _misses) == 0 ? 0.0 : _hits / (_hits + _misses);

  Box? get _box {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return null;
  }

  /// Looks up cached candidates for a given SearchCacheKey
  List<SearchCandidate>? get(SearchCacheKey key) {
    final box = _box;
    final serializedKey = key.serialize();

    if (box == null || !box.containsKey(serializedKey)) {
      _misses++;
      return null;
    }

    try {
      final raw = box.get(serializedKey);
      if (raw == null) {
        _misses++;
        return null;
      }

      final Map<String, dynamic> wrap = raw is String
          ? jsonDecode(raw) as Map<String, dynamic>
          : Map<String, dynamic>.from(raw as Map);

      // Check TTL
      final timestamp = wrap['timestamp'] as int? ?? 0;
      final entryAge = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (entryAge > defaultTtl.inMilliseconds) {
        box.delete(serializedKey);
        _misses++;
        return null;
      }

      // Update LRU access timestamp
      wrap['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      box.put(serializedKey, jsonEncode(wrap));

      final items = wrap['items'] as List? ?? [];
      final candidates = <SearchCandidate>[];

      for (final it in items) {
        if (it is Map) {
          final s = Map<String, dynamic>.from(it);
          final provStr = s['sourceProvider'] as String? ?? 'local';
          final prov = SearchProviderType.values.firstWhere(
            (p) => p.name == provStr,
            orElse: () => SearchProviderType.local,
          );

          candidates.add(SearchCandidate(
            canonicalId: s['canonicalId'] ?? s['id'] ?? '',
            youtubeId: s['youtubeId'],
            audiusId: s['audiusId'],
            jamendoId: s['jamendoId'],
            jioSaavnId: s['jioSaavnId'],
            spotifyId: s['spotifyId'],
            deezerId: s['deezerId'],
            isrc: s['isrc'],
            title: s['title'] ?? 'Unknown',
            artist: s['artist'] ?? 'Unknown',
            album: s['album'],
            channelOrOwner: s['channelOrOwner'],
            normalizedTitle: s['normalizedTitle'] ?? (s['title'] as String? ?? '').toLowerCase(),
            normalizedArtist: s['normalizedArtist'] ?? (s['artist'] as String? ?? '').toLowerCase(),
            normalizedAlbum: s['normalizedAlbum'],
            duration: Duration(seconds: s['durationSec'] ?? 180),
            language: s['language'],
            versionType: TrackVersionType.fromString(s['versionType']),
            sourceProvider: prov,
            viewCount: s['viewCount'],
            popularityScore: (s['popularityScore'] as num?)?.toDouble(),
            artworkUrl: s['artworkUrl'] ?? s['albumArt'],
            playableUrl: s['playableUrl'] ?? s['previewUrl'],
            previewUrl: s['previewUrl'],
            isDownloadable: s['isDownloadable'] == true,
            audioFormat: s['audioFormat'],
            bitrate: s['bitrate'],
          ));
        }
      }

      _hits++;
      debugPrint('[SearchCache] 🎯 Cache HIT for: "$serializedKey" (${candidates.length} items)');
      return candidates;
    } catch (e) {
      debugPrint('[SearchCache] ⚠️ Error parsing cache entry: $e');
      _misses++;
      return null;
    }
  }

  /// Stores candidates for a given SearchCacheKey with LRU eviction
  Future<void> put(SearchCacheKey key, List<SearchCandidate> candidates) async {
    final box = _box;
    if (box == null || candidates.isEmpty) return;

    final serializedKey = key.serialize();

    // Check LRU eviction if box size exceeds limit
    if (box.length >= maxCacheEntries) {
      final firstKey = box.keys.first;
      await box.delete(firstKey);
    }

    final serializedItems = candidates.map((c) => {
      'canonicalId': c.canonicalId,
      'youtubeId': c.youtubeId,
      'audiusId': c.audiusId,
      'jamendoId': c.jamendoId,
      'jioSaavnId': c.jioSaavnId,
      'spotifyId': c.spotifyId,
      'deezerId': c.deezerId,
      'isrc': c.isrc,
      'title': c.title,
      'artist': c.artist,
      'album': c.album,
      'channelOrOwner': c.channelOrOwner,
      'normalizedTitle': c.normalizedTitle,
      'normalizedArtist': c.normalizedArtist,
      'normalizedAlbum': c.normalizedAlbum,
      'durationSec': c.duration.inSeconds,
      'language': c.language,
      'versionType': c.versionType.name,
      'sourceProvider': c.sourceProvider.name,
      'viewCount': c.viewCount,
      'popularityScore': c.popularityScore,
      'artworkUrl': c.artworkUrl,
      'playableUrl': c.playableUrl,
      'previewUrl': c.previewUrl,
      'isDownloadable': c.isDownloadable,
      'audioFormat': c.audioFormat,
      'bitrate': c.bitrate,
    }).toList();

    final wrap = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'version': 2,
      'items': serializedItems,
    };

    await box.put(serializedKey, jsonEncode(wrap));
    debugPrint('[SearchCache] 💾 Cached ${candidates.length} items for "$serializedKey"');
  }

  Future<void> clear() async {
    final box = _box;
    if (box != null) {
      await box.clear();
      _hits = 0;
      _misses = 0;
    }
  }
}
