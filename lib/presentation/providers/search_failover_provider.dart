import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/search/failover_search_coordinator.dart';
import '../../core/search/models/search_models.dart';
import '../../core/search/pipeline/search_pipeline.dart';
import '../../core/search/search_cache_manager.dart';
import '../../core/search/search_debouncer.dart';
import '../../core/search/search_tier.dart';
import '../../core/search/telemetry/search_metrics.dart';
import '../../data/models/song_model.dart';

/// Status states for search pipeline
enum SearchStatus {
  idle,
  loading,
  success,
  fallbackActive,
  error,
}

/// Immutable state representation for the Multi-Provider Search
@immutable
class SearchFailoverState {
  final SearchStatus status;
  final String query;
  final List<SongModel> results;
  final List<RankedCandidate> rankedCandidates;
  final SearchTier? resolvedTier;
  final String? activeProviderName;
  final Duration? latency;
  final String? errorMessage;
  final int searchToken;
  final String? didYouMean;
  final List<String> autocompleteSuggestions;
  final Map<SearchProviderType, Duration> providerLatencies;
  final Map<SearchProviderType, int> providerCounts;
  final bool isFromCache;
  final bool isOffline;

  const SearchFailoverState({
    this.status = SearchStatus.idle,
    this.query = '',
    this.results = const [],
    this.rankedCandidates = const [],
    this.resolvedTier,
    this.activeProviderName,
    this.latency,
    this.errorMessage,
    this.searchToken = 0,
    this.didYouMean,
    this.autocompleteSuggestions = const [],
    this.providerLatencies = const {},
    this.providerCounts = const {},
    this.isFromCache = false,
    this.isOffline = false,
  });

  bool get isIdle => status == SearchStatus.idle;
  bool get isLoading => status == SearchStatus.loading;
  bool get isSuccess => status == SearchStatus.success;
  bool get isFallbackActive => status == SearchStatus.fallbackActive || isOffline || (resolvedTier == SearchTier.tier3LocalFailsafe);
  bool get isOfflineFallback => isOffline || resolvedTier == SearchTier.tier3LocalFailsafe;
  bool get isCached => isFromCache || resolvedTier == SearchTier.cache;
  bool get hasError => status == SearchStatus.error;
  bool get isEmpty => results.isEmpty && !isLoading && !isIdle;

  SearchFailoverState copyWith({
    SearchStatus? status,
    String? query,
    List<SongModel>? results,
    List<RankedCandidate>? rankedCandidates,
    SearchTier? resolvedTier,
    String? activeProviderName,
    Duration? latency,
    String? errorMessage,
    int? searchToken,
    String? didYouMean,
    List<String>? autocompleteSuggestions,
    Map<SearchProviderType, Duration>? providerLatencies,
    Map<SearchProviderType, int>? providerCounts,
    bool? isFromCache,
    bool? isOffline,
  }) {
    return SearchFailoverState(
      status: status ?? this.status,
      query: query ?? this.query,
      results: results ?? this.results,
      rankedCandidates: rankedCandidates ?? this.rankedCandidates,
      resolvedTier: resolvedTier ?? this.resolvedTier,
      activeProviderName: activeProviderName ?? this.activeProviderName,
      latency: latency ?? this.latency,
      errorMessage: errorMessage ?? this.errorMessage,
      searchToken: searchToken ?? this.searchToken,
      didYouMean: didYouMean ?? this.didYouMean,
      autocompleteSuggestions: autocompleteSuggestions ?? this.autocompleteSuggestions,
      providerLatencies: providerLatencies ?? this.providerLatencies,
      providerCounts: providerCounts ?? this.providerCounts,
      isFromCache: isFromCache ?? this.isFromCache,
      isOffline: isOffline ?? this.isOffline,
    );
  }
}

/// Riverpod StateNotifier managing the search pipeline execution lifecycle
class SearchFailoverNotifier extends StateNotifier<SearchFailoverState> {
  final SearchPipeline _pipeline;
  final FailoverSearchCoordinator _legacyCoordinator;
  final SearchDebouncer _debouncer;
  int _currentToken = 0;

  SearchFailoverNotifier({
    SearchPipeline? pipeline,
    FailoverSearchCoordinator? coordinator,
    SearchDebouncer? debouncer,
  })  : _pipeline = pipeline ?? SearchPipeline(),
        _legacyCoordinator = coordinator ?? FailoverSearchCoordinator(),
        _debouncer = debouncer ?? SearchDebouncer(delay: const Duration(milliseconds: 300)),
        super(const SearchFailoverState()) {
    _pipeline.autocomplete.init();
  }

  /// Handles real-time search input changes with 300ms debouncing and local autocomplete
  void onQueryChanged(String query) {
    final clean = query.trim();

    if (clean.isEmpty) {
      _debouncer.cancel();
      _currentToken++;
      state = const SearchFailoverState(status: SearchStatus.idle);
      return;
    }

    // Instant local autocomplete suggestions (<50ms)
    final suggestions = _pipeline.autocomplete.getSuggestions(clean);

    if (clean == state.query && (state.isSuccess || state.isLoading)) {
      state = state.copyWith(autocompleteSuggestions: suggestions);
      return;
    }

    state = state.copyWith(
      status: SearchStatus.loading,
      query: clean,
      autocompleteSuggestions: suggestions,
    );

    _debouncer.run(() {
      _executeSearchInternal(clean);
    });
  }

  /// Executes immediate query bypassing the 300ms debounce
  Future<void> searchImmediate(String query, {bool bypassCache = false, TrackVersionType? versionFilter}) async {
    _debouncer.cancel();
    final clean = query.trim();
    if (clean.isEmpty) {
      clear();
      return;
    }
    await _executeSearchInternal(clean, bypassCache: bypassCache, versionFilter: versionFilter);
  }

  /// Internal execution handler with race-condition token guard
  Future<void> _executeSearchInternal(String query, {bool bypassCache = false, TrackVersionType? versionFilter}) async {
    final token = ++_currentToken;

    state = state.copyWith(
      status: SearchStatus.loading,
      query: query,
      errorMessage: null,
      searchToken: token,
    );

    try {
      final request = SearchRequest(
        query: query,
        preferredVersion: versionFilter,
      );

      final response = await _pipeline.execute(request);

      // Discard stale responses from out-of-order asynchronous completions
      if (_currentToken != token) {
        debugPrint('[SearchFailoverNotifier] Stale query response ignored for "$query"');
        return;
      }

      SearchMetrics.logSearch(response);

      final songModels = response.songs.map((s) => SongModel(
        id: s.id,
        title: s.title,
        artist: s.artist,
        albumArt: s.albumArt,
        album: s.album,
        duration: s.duration,
        youtubeUrl: s.youtubeUrl,
        deezerUrl: s.deezerUrl,
        previewUrl: s.previewUrl,
        language: s.language,
        isYoutubeImport: s.isYoutubeImport,
        bitrate: s.bitrate,
        formatId: s.formatId,
      )).toList();

      final isOffline = response.isOfflineFallback;
      final status = isOffline ? SearchStatus.fallbackActive : SearchStatus.success;

      state = state.copyWith(
        status: status,
        results: songModels,
        rankedCandidates: response.rankedResults,
        resolvedTier: response.isFromCache ? SearchTier.cache : (isOffline ? SearchTier.tier3LocalFailsafe : SearchTier.tier1MongoAtlas),
        activeProviderName: response.rankedResults.isNotEmpty ? response.rankedResults.first.candidate.sourceProvider.displayName : 'Aura Search Engine',
        latency: response.totalLatency,
        errorMessage: null,
        didYouMean: response.didYouMean,
        autocompleteSuggestions: response.autocompleteSuggestions,
        providerLatencies: response.providerLatencies,
        providerCounts: response.providerCandidateCounts,
        isFromCache: response.isFromCache,
        isOffline: isOffline,
      );
    } catch (e) {
      if (_currentToken != token) return;

      // Fallback to legacy coordinator if pipeline threw an unexpected exception
      try {
        final legacyRes = await _legacyCoordinator.executeSearch(query, bypassCache: bypassCache);
        if (_currentToken != token) return;

        state = state.copyWith(
          status: legacyRes.tier == SearchTier.tier3LocalFailsafe ? SearchStatus.fallbackActive : SearchStatus.success,
          results: legacyRes.songs,
          resolvedTier: legacyRes.tier,
          activeProviderName: legacyRes.providerName,
          latency: legacyRes.latency,
          errorMessage: null,
        );
      } catch (legacyErr) {
        state = state.copyWith(
          status: SearchStatus.error,
          errorMessage: legacyErr.toString(),
        );
      }
    }
  }

  /// Clears search state and active debounce timers
  void clear() {
    _debouncer.cancel();
    _currentToken++;
    state = const SearchFailoverState(status: SearchStatus.idle);
  }

  /// Refreshes current query
  Future<void> refresh() async {
    if (state.query.isNotEmpty) {
      await searchImmediate(state.query, bypassCache: true);
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _legacyCoordinator.dispose();
    super.dispose();
  }
}

// ── Riverpod Providers ────────────────────────────────────────────────────────

/// Global SearchPipeline provider
final searchPipelineProvider = Provider<SearchPipeline>((ref) {
  return SearchPipeline();
});

/// Global provider for the Cache Manager
final searchCacheManagerProvider = Provider<SearchCacheManager>((ref) {
  return SearchCacheManager();
});

/// Global provider for the Failover Search Coordinator
final failoverCoordinatorProvider = Provider<FailoverSearchCoordinator>((ref) {
  final cacheManager = ref.watch(searchCacheManagerProvider);
  final coordinator = FailoverSearchCoordinator(cacheManager: cacheManager);
  ref.onDispose(() => coordinator.dispose());
  return coordinator;
});

/// Riverpod StateNotifierProvider driving the search UI
final searchFailoverProvider =
    StateNotifierProvider<SearchFailoverNotifier, SearchFailoverState>((ref) {
  final pipeline = ref.watch(searchPipelineProvider);
  final coordinator = ref.watch(failoverCoordinatorProvider);
  return SearchFailoverNotifier(pipeline: pipeline, coordinator: coordinator);
});
