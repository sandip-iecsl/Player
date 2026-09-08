import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/search/failover_search_coordinator.dart';
import '../../core/search/search_cache_manager.dart';
import '../../core/search/search_debouncer.dart';
import '../../core/search/search_tier.dart';
import '../../data/models/song_model.dart';

/// Status states for search pipeline
enum SearchStatus {
  idle,
  loading,
  success,
  fallbackActive,
  error,
}

/// Immutable state representation for the Multi-Provider Failover Search
@immutable
class SearchFailoverState {
  final SearchStatus status;
  final String query;
  final List<SongModel> results;
  final SearchTier? resolvedTier;
  final String? activeProviderName;
  final Duration? latency;
  final String? errorMessage;
  final int searchToken;

  const SearchFailoverState({
    this.status = SearchStatus.idle,
    this.query = '',
    this.results = const [],
    this.resolvedTier,
    this.activeProviderName,
    this.latency,
    this.errorMessage,
    this.searchToken = 0,
  });

  bool get isIdle => status == SearchStatus.idle;
  bool get isLoading => status == SearchStatus.loading;
  bool get isSuccess => status == SearchStatus.success;
  bool get isFallbackActive => status == SearchStatus.fallbackActive || (resolvedTier == SearchTier.tier3LocalFailsafe);
  bool get isOfflineFallback => resolvedTier == SearchTier.tier3LocalFailsafe;
  bool get isCached => resolvedTier == SearchTier.cache;
  bool get hasError => status == SearchStatus.error;
  bool get isEmpty => results.isEmpty && !isLoading && !isIdle;

  SearchFailoverState copyWith({
    SearchStatus? status,
    String? query,
    List<SongModel>? results,
    SearchTier? resolvedTier,
    String? activeProviderName,
    Duration? latency,
    String? errorMessage,
    int? searchToken,
  }) {
    return SearchFailoverState(
      status: status ?? this.status,
      query: query ?? this.query,
      results: results ?? this.results,
      resolvedTier: resolvedTier ?? this.resolvedTier,
      activeProviderName: activeProviderName ?? this.activeProviderName,
      latency: latency ?? this.latency,
      errorMessage: errorMessage ?? this.errorMessage,
      searchToken: searchToken ?? this.searchToken,
    );
  }
}

/// Riverpod StateNotifier managing the failover search execution lifecycle
class SearchFailoverNotifier extends StateNotifier<SearchFailoverState> {
  final FailoverSearchCoordinator _coordinator;
  final SearchDebouncer _debouncer;
  int _currentToken = 0;

  SearchFailoverNotifier({
    FailoverSearchCoordinator? coordinator,
    SearchDebouncer? debouncer,
  })  : _coordinator = coordinator ?? FailoverSearchCoordinator(),
        _debouncer = debouncer ?? SearchDebouncer(delay: const Duration(milliseconds: 300)),
        super(const SearchFailoverState());

  /// Handles real-time search input changes with 300ms debouncing and 0-cost local cache check
  void onQueryChanged(String query) {
    final clean = query.trim();

    if (clean.isEmpty) {
      _debouncer.cancel();
      _currentToken++;
      state = const SearchFailoverState(status: SearchStatus.idle);
      return;
    }

    if (clean == state.query && (state.isSuccess || state.isLoading)) {
      return;
    }

    // Set loading preview state immediately while debounce timer runs
    state = state.copyWith(
      status: SearchStatus.loading,
      query: clean,
    );

    _debouncer.run(() {
      _executeSearchInternal(clean);
    });
  }

  /// Executes immediate query bypassing the 300ms debounce
  Future<void> searchImmediate(String query, {bool bypassCache = false}) async {
    _debouncer.cancel();
    final clean = query.trim();
    if (clean.isEmpty) {
      clear();
      return;
    }
    await _executeSearchInternal(clean, bypassCache: bypassCache);
  }

  /// Internal execution handler with race-condition token guard
  Future<void> _executeSearchInternal(String query, {bool bypassCache = false}) async {
    final token = ++_currentToken;

    state = state.copyWith(
      status: SearchStatus.loading,
      query: query,
      errorMessage: null,
      searchToken: token,
    );

    try {
      final resultPayload = await _coordinator.executeSearch(query, bypassCache: bypassCache);

      // Discard stale responses from out-of-order asynchronous completions
      if (_currentToken != token) {
        debugPrint('[SearchFailoverNotifier] Stale query response ignored for "$query" (Token $token != $_currentToken)');
        return;
      }

      final isTier3 = resultPayload.tier == SearchTier.tier3LocalFailsafe;
      final newStatus = isTier3 ? SearchStatus.fallbackActive : SearchStatus.success;

      state = state.copyWith(
        status: newStatus,
        results: resultPayload.songs,
        resolvedTier: resultPayload.tier,
        activeProviderName: resultPayload.providerName,
        latency: resultPayload.latency,
        errorMessage: null,
      );
    } catch (e) {
      if (_currentToken != token) return;

      state = state.copyWith(
        status: SearchStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Clears search state and active debounce timers
  void clear() {
    _debouncer.cancel();
    _currentToken++;
    state = const SearchFailoverState(status: SearchStatus.idle);
  }

  /// Refreshes the current query results forcing cloud/failover bypass of local cache
  Future<void> refresh() async {
    if (state.query.isNotEmpty) {
      await searchImmediate(state.query, bypassCache: true);
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _coordinator.dispose();
    super.dispose();
  }
}

// ── Riverpod Provider Singletons ─────────────────────────────────────────────

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
  final coordinator = ref.watch(failoverCoordinatorProvider);
  return SearchFailoverNotifier(coordinator: coordinator);
});
