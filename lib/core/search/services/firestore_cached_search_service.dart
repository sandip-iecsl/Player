import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../data/models/song_model.dart';
import '../normalization/ngram_tokenizer.dart';
import '../ranking/youtube_relevance_ranker.dart';
import '../search_cache_manager.dart';
import '../search_debouncer.dart';
import '../search_tier.dart';

/// Free-Tier Optimized Firestore Cached Search Service with YouTube-Style Ranking
/// 
/// 1. 300ms Keystroke Debouncer to prevent rapid database operations
/// 2. 0ms Local Hive Cache check (`search_cache_box`)
/// 3. Firestore `searchTokens` array-contains query (Free tier optimized)
/// 4. Multi-factor YouTube relevance & velocity ranking
class FirestoreCachedSearchService {
  final FirebaseFirestore _firestore;
  final SearchCacheManager _cacheManager;
  final SearchDebouncer _debouncer;
  final YouTubeRelevanceRanker _ranker;

  FirestoreCachedSearchService({
    FirebaseFirestore? firestore,
    SearchCacheManager? cacheManager,
    SearchDebouncer? debouncer,
    YouTubeRelevanceRanker? ranker,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _cacheManager = cacheManager ?? SearchCacheManager(),
        _debouncer = debouncer ?? SearchDebouncer(delay: const Duration(milliseconds: 300)),
        _ranker = ranker ?? const YouTubeRelevanceRanker();

  /// Debounced search trigger for user input streams
  void debouncedSearch({
    required String query,
    required void Function(List<SongModel> results, SearchTier tier, bool isFromCache) onResults,
    void Function(String error)? onError,
  }) {
    final clean = query.trim();
    if (clean.isEmpty) {
      _debouncer.cancel();
      onResults([], SearchTier.cache, true);
      return;
    }

    _debouncer.run(() async {
      try {
        final result = await search(clean);
        onResults(result.songs, result.tier, result.isFromCache);
      } catch (e) {
        if (onError != null) onError(e.toString());
      }
    });
  }

  /// Executes search pipeline: Cache Check -> Firestore Array-Contains -> Multi-Factor Ranking
  Future<({List<SongModel> songs, SearchTier tier, bool isFromCache})> search(
    String query, {
    bool bypassCache = false,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      return (songs: <SongModel>[], tier: SearchTier.cache, isFromCache: true);
    }

    final normalizedKey = NGramTokenizer.normalize(clean);

    // ── STEP 1: Hive Local Cache Check (0ms - 0 Cloud Cost) ──────────────────
    if (!bypassCache) {
      final cached = await _cacheManager.getCachedResults(normalizedKey);
      if (cached != null && cached.isNotEmpty) {
        debugPrint('[FirestoreSearch] ⚡ 0-Cost Cache HIT for "$clean"');
        return (songs: cached.songs, tier: SearchTier.cache, isFromCache: true);
      }
    }

    // ── STEP 2: Firestore Array-Contains Query ──────────────────────────────
    debugPrint('[FirestoreSearch] 🌐 Cache MISS. Executing Firestore token query for: "$normalizedKey"');
    List<SongModel> rawCandidates = [];

    try {
      final snapshot = await _firestore
          .collection('songs')
          .where('searchTokens', arrayContains: normalizedKey)
          .limit(40)
          .get(const GetOptions(source: Source.serverAndCache));

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          data['id'] = doc.id;
          rawCandidates.add(SongModel.fromJson(data));
        } catch (parseErr) {
          debugPrint('[FirestoreSearch] Document parse note: $parseErr');
        }
      }
    } catch (firestoreErr) {
      debugPrint('[FirestoreSearch] ⚠️ Firestore lookup warning: $firestoreErr');
    }

    // ── STEP 3: Multi-Factor YouTube Relevance & Velocity Ranking ───────────
    final rankedResults = _ranker.rank(
      query: clean,
      candidates: rawCandidates,
    );

    // ── STEP 4: Cache response in Hive for future instant hits ───────────────
    if (rankedResults.isNotEmpty) {
      unawaited(_cacheManager.cacheResults(normalizedKey, rankedResults).catchError((_) {}));
    }

    return (
      songs: rankedResults,
      tier: SearchTier.tier1MongoAtlas, // Cloud resolved
      isFromCache: false,
    );
  }

  void dispose() {
    _debouncer.dispose();
  }
}
