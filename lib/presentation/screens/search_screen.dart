import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';
import '../../data/services/audio_service.dart'; // PlaybackContext
import '../../data/services/global_firebase_engine.dart';
import '../../data/services/hybrid_search_service.dart';
import '../providers/audio_provider.dart';
import '../providers/music_data_providers.dart';
import '../providers/history_provider.dart';
import '../widgets/playlist_dialogs.dart';
import '../widgets/skeleton_shimmer.dart';
import '../../core/constants/app_colors.dart';
import '../providers/theme_provider.dart';

import '../widgets/import_link_modal.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => SearchScreenState();
}

// Public so MainScreen can call clearState() via GlobalKey<SearchScreenState>
class SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  
  // _liveQuery: what the user types (shown in search bar)
  // _submittedQuery: triggers the API call
  String _liveQuery = '';
  String _submittedQuery = '';
  String _debouncedQuery = '';
  bool _showResults = false;
  
  // Pagination state
  List<Song> _allResults = [];
  bool _isLoadingMore = false;
  bool _hasMoreResults = true;
  int _currentPage = 1;
  static const int _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    debugPrint('[SearchScreen] 🎯 Initialized with scroll listener');
  }

  @override
  void dispose() {
    debugPrint('[SearchScreen] 🗑️ Disposing search screen');
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      debugPrint('[SearchScreen] ⚠️ Scroll controller has no clients');
      return;
    }
    
    final position = _scrollController.position;
    final threshold = position.maxScrollExtent - 200;
    final currentPixels = position.pixels;
    
    // Periodic logging every 500px to track scrolling
    if (currentPixels % 500 < 50) {
      debugPrint('[SearchScreen] 📊 Scroll position: $currentPixels / ${position.maxScrollExtent} (threshold: $threshold)');
    }
    
    if (currentPixels >= threshold) {
      // User is near the bottom, load more
      if (!_isLoadingMore && _hasMoreResults && _submittedQuery.isNotEmpty) {
        debugPrint('[SearchScreen] 📜 Scroll threshold reached! Loading more... (page: $_currentPage)');
        _loadMoreResults();
      } else {
        if (_isLoadingMore) {
          debugPrint('[SearchScreen] ⏳ Already loading...');
        } else if (!_hasMoreResults) {
          debugPrint('[SearchScreen] 🏁 No more results to load');
        } else if (_submittedQuery.isEmpty) {
          debugPrint('[SearchScreen] ❓ No query submitted');
        }
      }
    }
  }

  Future<void> _loadMoreResults() async {
    if (_isLoadingMore || !_hasMoreResults) {
      debugPrint('[SearchScreen] ⚠️ Skip loading: isLoading=$_isLoadingMore, hasMore=$_hasMoreResults');
      return;
    }
    
    debugPrint('[SearchScreen] 🔄 Loading page $_currentPage (offset: ${_currentPage * _pageSize})');
    setState(() => _isLoadingMore = true);
    
    try {
      final service = ref.read(hybridSearchServiceProvider);
      final newResults = await service.searchSongs(
        _submittedQuery,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
      );
      
      debugPrint('[SearchScreen] ✅ Got ${newResults.length} new results');
      
      if (mounted) {
        setState(() {
          if (newResults.isEmpty) {
            debugPrint('[SearchScreen] 🛑 No more results available');
            _hasMoreResults = false;
          }
          // Filter out duplicates
          final existingIds = _allResults.map((s) => s.id).toSet();
          final uniqueNewResults = newResults.where((s) => !existingIds.contains(s.id)).toList();
          
          debugPrint('[SearchScreen] ➕ Adding ${uniqueNewResults.length} unique results (${newResults.length - uniqueNewResults.length} duplicates filtered)');
          _allResults.addAll(uniqueNewResults);
          _currentPage++;
          _isLoadingMore = false;
          
          debugPrint('[SearchScreen] 📊 Total results now: ${_allResults.length}');

          // Sync with active queue if user is playing from this search query
          final audio = ref.read(audioServiceProvider);
          if (audio.currentContext == PlaybackContext.search && audio.currentContextId == _submittedQuery) {
            audio.appendSongs(uniqueNewResults);
          }
        });
        _checkAndFallbackUnstreamableTracks();
      }
    } catch (e) {
      debugPrint('[SearchScreen] ❌ Error loading more results: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _resetPagination() {
    debugPrint('[SearchScreen] 🔄 Resetting pagination');
    _allResults = [];
    _currentPage = 1;
    _hasMoreResults = true;
    _isLoadingMore = false;
  }

  Future<void> _checkAndFallbackUnstreamableTracks() async {
    for (int i = 0; i < _allResults.length; i++) {
      final song = _allResults[i];
      if (song.previewUrl == null || song.previewUrl!.startsWith('unstreamable')) {
        debugPrint('[SearchScreen] 🔄 Firing background remix fallback for unstreamable track: ${song.title}');
        try {
          final searchService = HybridSearchService();
          final fallbackQuery = '${song.title} ${song.artist} remix';
          final results = await searchService.searchSongs(fallbackQuery, limit: 3);
          
          final validFallback = results.where((s) => s.previewUrl != null && !s.previewUrl!.startsWith('unstreamable')).toList();
          
          if (validFallback.isNotEmpty) {
            if (mounted) {
              setState(() {
                _allResults[i] = validFallback.first;
              });
              debugPrint('[SearchScreen] ✅ Unstreamable track replaced with remix fallback!');
            }
          }
        } catch (_) {}
      }
    }
  }

  /// Called when the user presses Enter or taps Search.
  void _onSubmit(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    ref.read(searchHistoryProvider.notifier).add(q);
    _logSearchQuery(q);
    _resetPagination(); // Reset pagination for new search
    setState(() {
      _submittedQuery = q;
      _showResults = true;
    });
    _focusNode.unfocus();
  }

  void _onHistoryTap(String query) {
    _searchController.text = query;
    _logSearchQuery(query);
    _resetPagination(); // Reset pagination for new search
    setState(() {
      _liveQuery = query;
      _submittedQuery = query;
      _showResults = true;
    });
    _focusNode.unfocus();
  }

  Future<void> _logSearchQuery(String query) async {
    try {
      final engine = GlobalFirebaseEngine();
      await engine.logSearchQuery(query);
    } catch (_) {}
  }

  void _clearSearch() {
    _searchController.clear();
    _resetPagination(); // Reset pagination when clearing
    setState(() {
      _liveQuery = '';
      _submittedQuery = '';
      _debouncedQuery = '';
      _showResults = false;
    });
  }

  /// Called by MainScreen when this tab is deselected — clears state.
  void clearState() {
    _searchController.clear();
    _resetPagination(); // Reset pagination when clearing
    if (mounted) {
      setState(() {
        _liveQuery = '';
        _submittedQuery = '';
        _debouncedQuery = '';
        _showResults = false;
      });
    }
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeModeProvider);
    ref.watch(themeColorProvider);
    final searchHistory = ref.watch(searchHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.deepSpaceBlack,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Search',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  InkWell(
                    onTap: () => ImportLinkModal.show(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_rounded, color: Colors.redAccent, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Import Link',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                onChanged: (val) {
                  setState(() {
                    _liveQuery = val;
                    _showResults = false;
                  });
                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      setState(() => _debouncedQuery = val.trim());
                    }
                  });
                },
                onSubmitted: _onSubmit,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search songs or paste YouTube link...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                  suffixIcon: _liveQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close, color: AppColors.textSecondary),
                          onPressed: _clearSearch,
                        )
                      : IconButton(
                          icon: const Icon(Icons.link_rounded, color: Colors.redAccent, size: 20),
                          tooltip: 'Paste Link to Play',
                          onPressed: () => ImportLinkModal.show(context),
                        ),
                  filled: true,
                  fillColor: AppColors.deepSpaceBlackLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: _liveQuery.isEmpty
                  ? _buildHistory(searchHistory)
                  : (_showResults
                      ? _buildResults()
                      : _buildSuggestions(_debouncedQuery)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions(String query) {
    if (query.trim().isEmpty) return const SizedBox.shrink();
    return Consumer(
      builder: (context, ref, _) {
        final suggestionsAsync = ref.watch(autocompleteSuggestionsProvider(query));

        return suggestionsAsync.when(
          data: (data) {
            final songs = data['songs'] as List<Song>? ?? [];
            final albums = data['albums'] ?? [];
            final artists = data['artists'] ?? [];

            if (songs.isEmpty && albums.isEmpty && artists.isEmpty) {
              return Center(
                child: Text('No recommendations...', style: TextStyle(color: AppColors.textSecondary)),
              );
            }

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (songs.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('Songs', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  ...songs.take(5).map((song) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: song.albumArt != null
                          ? Image.network(song.albumArt!, width: 40, height: 40, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(width: 40, height: 40, color: AppColors.deepSpaceBlackLighter, child: Icon(Icons.music_note, color: AppColors.textPrimary, size: 20)))
                          : Container(width: 40, height: 40, color: AppColors.deepSpaceBlackLighter, child: Icon(Icons.music_note, color: AppColors.textPrimary, size: 20)),
                    ),
                    title: Text(song.title, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                    subtitle: Text('Song • ${song.artist}', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    onTap: () {
                      _searchController.text = song.title;
                      _resetPagination();
                      _logSearchQuery(song.title);
                      setState(() {
                        _liveQuery = song.title;
                        _submittedQuery = song.title;
                        _showResults = true;
                      });
                      _focusNode.unfocus();
                    },
                  )),
                ],
                if (albums.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('Albums', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  ...albums.take(3).map((album) {
                    final title = album['title']?.toString() ?? '';
                    final subtitle = album['subtitle']?.toString() ?? '';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.album, color: AppColors.textSecondary),
                      title: Text(title, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                      subtitle: Text('Album • $subtitle', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      onTap: () {
                        _searchController.text = title;
                        _resetPagination();
                        _logSearchQuery(title);
                        setState(() {
                          _liveQuery = title;
                          _submittedQuery = title;
                          _showResults = true;
                        });
                        _focusNode.unfocus();
                      },
                    );
                  }),
                ],
                if (artists.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('Artists', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  ...artists.take(3).map((artist) {
                    final title = artist['title']?.toString() ?? '';
                    final description = artist['description']?.toString() ?? '';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person, color: AppColors.textSecondary),
                      title: Text(title, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                      subtitle: Text('Artist • $description', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      onTap: () {
                        _searchController.text = title;
                        _resetPagination();
                        _logSearchQuery(title);
                        setState(() {
                          _liveQuery = title;
                          _submittedQuery = title;
                          _showResults = true;
                        });
                        _focusNode.unfocus();
                      },
                    );
                  }),
                ],
              ],
            );
          },
          loading: () => ListView.builder(
            itemCount: 5,
            itemBuilder: (context, index) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: SkeletonShimmer(child: SkeletonSongTile()),
            ),
          ),
          error: (err, _) => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildHistory(List<String> history) {
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, color: AppColors.textSecondary, size: 60),
            SizedBox(height: 16),
            Text(
              'Search for songs, artists, albums',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent searches',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
              child: Text('Clear all', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...history.map((query) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.history, color: AppColors.textSecondary),
          title: Text(query, style: TextStyle(color: AppColors.textPrimary)),
          trailing: IconButton(
            icon: Icon(Icons.close, color: AppColors.textSecondary, size: 18),
            onPressed: () => ref.read(searchHistoryProvider.notifier).remove(query),
          ),
          onTap: () => _onHistoryTap(query),
        )),
      ],
    );
  }

  Widget _buildResults() {
    return Consumer(
      builder: (context, ref, _) {
        // ONLY fire API on submitted query, not on every keystroke
        final searchResultsAsync = ref.watch(searchSongsProvider(_submittedQuery));
        final trendingSongsAsync = ref.watch(trendingMusicProvider);

        return searchResultsAsync.when(
          data: (songs) {
            debugPrint('[SearchScreen] Provider returned ${songs.length} songs for "$_submittedQuery"');
            
            // Initialize _allResults with first page ONLY if it's empty and we're on page 1
            if (_allResults.isEmpty && songs.isNotEmpty && _currentPage == 1) {
              // Use post frame to avoid setState during build
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _currentPage == 1) {
                  setState(() {
                    _allResults = List.from(songs);
                    _hasMoreResults = true; // Always allow fetching next page
                  });
                  _checkAndFallbackUnstreamableTracks(); // Trigger fallback loop
                  debugPrint('[SearchScreen] Initialized with ${_allResults.length} results');
                }
              });
            }
            
            final trendingSongs = trendingSongsAsync.valueOrNull ?? [];
            final queryClean = _submittedQuery.toLowerCase().replaceAll(RegExp(r'\s+'), '');
            final matchedTrending = trendingSongs.where((s) {
              final titleClean = s.title.toLowerCase().replaceAll(RegExp(r'\s+'), '');
              final artistClean = s.artist.toLowerCase().replaceAll(RegExp(r'\s+'), '');
              return titleClean.contains(queryClean) || artistClean.contains(queryClean);
            }).toList();
            
            // Use paginated results if available, otherwise show initial results
            final displayResults = _allResults.isNotEmpty ? _allResults : songs;
            
            debugPrint('[SearchScreen] Displaying ${displayResults.length} total results, loading more: $_isLoadingMore, has more: $_hasMoreResults');

            if (displayResults.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.music_off_rounded, color: AppColors.textSecondary, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'No tracks found for "$_submittedQuery"',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try searching for something else, or check out today\'s trending hits below:',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Expanded(
                      child: trendingSongsAsync.when(
                        data: (trending) {
                          if (trending.isEmpty) return const SizedBox.shrink();
                          return ListView.builder(
                            itemCount: trending.length,
                            itemBuilder: (context, index) {
                              final song = trending[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: song.albumArt != null
                                      ? Image.network(song.albumArt!, width: 40, height: 40, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(width: 40, height: 40, color: AppColors.deepSpaceBlackLighter, child: Icon(Icons.music_note, color: AppColors.textPrimary)))
                                      : Container(width: 40, height: 40, color: AppColors.deepSpaceBlackLighter, child: Icon(Icons.music_note, color: AppColors.textPrimary)),
                                ),
                                title: Text(song.title, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                                subtitle: Text(song.artist, style: TextStyle(color: AppColors.textSecondary)),
                                onTap: () {
                                  ref.read(audioServiceProvider).loadQueue(
                                    trending,
                                    startIndex: index,
                                    context: PlaybackContext.search,
                                  );
                                  ref.read(recentlyPlayedProvider.notifier).add(song);
                                },
                              );
                            },
                          );
                        },
                        loading: () => ListView.builder(
                          itemCount: 5,
                          itemBuilder: (context, index) => const SkeletonShimmer(child: SkeletonSongTile()),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 100, left: 16, right: 16, top: 16),
              itemCount: displayResults.length + 1 + (_hasMoreResults ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == displayResults.length + 1) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: SkeletonShimmer(child: SkeletonSongTile()),
                  );
                }

                final queryClean = _submittedQuery.toLowerCase().trim();
                final isArtistSearch = displayResults.isNotEmpty && 
                    displayResults.take(3).every((s) => s.artist.toLowerCase().contains(queryClean));

                if (index == 0) {
                  if (isArtistSearch) {
                    final topSongs = displayResults.take(20).toList();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: _buildTopArtistSlider(topSongs, context, ref, displayResults),
                    );
                  } else {
                    final topSong = displayResults[0];
                    final isPlaying = ref.watch(currentSongProvider).valueOrNull?.id == topSong.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: _buildTopResultCard(topSong, isPlaying, context, ref, displayResults),
                    );
                  }
                }

                if (index == 1) {
                  if (displayResults.length == 1) return const SizedBox.shrink();
                  return Padding(
                    padding: EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      'Songs',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  );
                }
                
                final songIndex = index - 1;
                final song = displayResults[songIndex];
                final isPlaying = ref.watch(currentSongProvider).valueOrNull?.id == song.id;
                final isTrending = matchedTrending.any((t) => t.id == song.id);

                return SearchSongTile(
                  song: song,
                  isPlaying: isPlaying,
                  isTrending: isTrending,
                  displayResults: displayResults,
                  index: songIndex,
                  submittedQuery: _submittedQuery,
                );
              },
            );
          },
          loading: () => ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 8,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 24.0),
                  child: SkeletonShimmer(child: SkeletonTopResultCard()),
                );
              }
              return const SkeletonShimmer(child: SkeletonSongTile());
            },
          ),
          error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: AppColors.neonCoral))),
        );
      },
    );
  }

  Widget _buildTopResultCard(Song song, bool isPlaying, BuildContext context, WidgetRef ref, List<Song> allResults) {
    return GestureDetector(
      onTap: () {
        ref.read(audioServiceProvider).loadQueue(
          allResults,
          startIndex: 0,
          context: PlaybackContext.search,
          contextId: _submittedQuery,
        );
        ref.read(recentlyPlayedProvider.notifier).add(song);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.deepSpaceBlackLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: song.albumArt != null
                  ? Image.network(song.albumArt!, width: 92, height: 92, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 92, height: 92, color: AppColors.deepSpaceBlackLighter, child: Icon(Icons.music_note, color: AppColors.textPrimary, size: 40)))
                  : Container(width: 92, height: 92, color: AppColors.deepSpaceBlackLighter, child: Icon(Icons.music_note, color: AppColors.textPrimary, size: 40)),
            ),
            const SizedBox(height: 20),
            Text(
              song.title,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.neonPink,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('Song', style: TextStyle(color: AppColors.deepSpaceBlack, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    song.artist,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopArtistSlider(List<Song> artistSongs, BuildContext context, WidgetRef ref, List<Song> allResults) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Tracks',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 204,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: artistSongs.length,
            itemBuilder: (context, index) {
              final song = artistSongs[index];
              return GestureDetector(
                onTap: () {
                  ref.read(audioServiceProvider).loadQueue(
                    allResults,
                    startIndex: index,
                    context: PlaybackContext.search,
                    contextId: _submittedQuery,
                  );
                  ref.read(recentlyPlayedProvider.notifier).add(song);
                },
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.deepSpaceBlackLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: song.albumArt != null
                            ? Image.network(song.albumArt!, width: 116, height: 116, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(width: 116, height: 116, color: AppColors.deepSpaceBlackLighter, child: Icon(Icons.music_note, color: AppColors.textPrimary, size: 40)))
                            : Container(width: 116, height: 116, color: AppColors.deepSpaceBlackLighter, child: Icon(Icons.music_note, color: AppColors.textPrimary, size: 40)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        song.title,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artist,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class SearchSongTile extends ConsumerStatefulWidget {
  final Song song;
  final bool isPlaying;
  final bool isTrending;
  final List<Song> displayResults;
  final int index;
  final String submittedQuery;

  const SearchSongTile({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.isTrending,
    required this.displayResults,
    required this.index,
    required this.submittedQuery,
  });

  @override
  ConsumerState<SearchSongTile> createState() => _SearchSongTileState();
}

class _SearchSongTileState extends ConsumerState<SearchSongTile> {
  bool _showAlternatives = false;
  List<Song> _alternatives = [];
  bool _isLoadingAlternatives = false;

  Future<void> _fetchAlternatives() async {
    if (_alternatives.isNotEmpty || _isLoadingAlternatives) return;
    setState(() => _isLoadingAlternatives = true);
    try {
      final service = ref.read(hybridSearchServiceProvider);
      final results = await service.searchSongs('${widget.song.title} ${widget.song.artist}', limit: 5);
      final filtered = results.where((s) => s.id != widget.song.id && s.previewUrl != null && s.previewUrl!.isNotEmpty).toList();
      if (mounted) {
        setState(() {
          _alternatives = filtered;
          _isLoadingAlternatives = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingAlternatives = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAvailable = widget.song.previewUrl != null && widget.song.previewUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Opacity(
                  opacity: isAvailable ? 1.0 : 0.4,
                  child: widget.song.albumArt != null
                      ? Image.network(
                          widget.song.albumArt!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 50,
                            height: 50,
                            color: AppColors.deepSpaceBlackLighter,
                            child: Icon(Icons.music_note, color: AppColors.textPrimary),
                          ),
                        )
                      : Container(
                          width: 50,
                          height: 50,
                          color: AppColors.deepSpaceBlackLighter,
                          child: Icon(Icons.music_note, color: AppColors.textPrimary),
                        ),
                ),
              ),
              if (widget.isTrending)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: AppColors.neonPink, shape: BoxShape.circle),
                    child: Icon(Icons.trending_up, color: AppColors.deepSpaceBlack, size: 10),
                  ),
                ),
            ],
          ),
          title: Text(
            widget.song.title,
            style: TextStyle(
              color: widget.isPlaying
                  ? AppColors.neonPink
                  : (isAvailable ? AppColors.textPrimary : AppColors.textSecondary),
              fontWeight: FontWeight.w600,
              decoration: isAvailable ? null : TextDecoration.lineThrough,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              if (!isAvailable) ...[
                Icon(Icons.warning_amber_rounded, color: AppColors.neonCoral, size: 14),
                SizedBox(width: 4),
                Text(
                  'Unavailable • ',
                  style: TextStyle(color: AppColors.neonCoral, fontSize: 12),
                ),
              ],
              Expanded(
                child: Text(
                  widget.isTrending ? 'Trending • ${widget.song.artist}' : widget.song.artist,
                  style: TextStyle(color: isAvailable ? AppColors.textSecondary : AppColors.divider),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          trailing: isAvailable
              ? (widget.isPlaying
                  ? Icon(Icons.equalizer_rounded, color: AppColors.neonPink)
                  : IconButton(
                      icon: Icon(Icons.more_vert, color: AppColors.textSecondary),
                      onPressed: () => PlaylistDialogs.showSongOptions(context, ref, widget.song),
                    ))
              : TextButton(
                  onPressed: () {
                    setState(() => _showAlternatives = !_showAlternatives);
                    if (_showAlternatives) {
                      _fetchAlternatives();
                    }
                  },
                  child: Text(
                    _showAlternatives ? 'Hide' : 'Alternates',
                    style: TextStyle(color: AppColors.neonPink, fontSize: 12),
                  ),
                ),
          onTap: isAvailable
              ? () {
                  ref.read(audioServiceProvider).loadQueue(
                    widget.displayResults,
                    startIndex: widget.index,
                    context: PlaybackContext.search,
                    contextId: widget.submittedQuery,
                  );
                  ref.read(recentlyPlayedProvider.notifier).add(widget.song);
                  if (widget.submittedQuery.isNotEmpty) {
                    ref.read(searchHistoryProvider.notifier).add(widget.submittedQuery);
                  }
                }
              : null,
        ),
        if (!isAvailable && _showAlternatives)
          Padding(
            padding: const EdgeInsets.only(left: 66.0, right: 16.0, bottom: 8.0),
            child: _isLoadingAlternatives
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonPink),
                  )
                : (_alternatives.isEmpty
                    ? Text(
                        'No alternative versions found.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alternatives:',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          ..._alternatives.map((alt) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.play_circle_outline, color: AppColors.neonPink, size: 20),
                                title: Text(
                                  alt.title,
                                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${alt.artist} • ${alt.album ?? "Single"}',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  ref.read(audioServiceProvider).loadQueue(
                                    [alt],
                                    startIndex: 0,
                                    context: PlaybackContext.search,
                                    contextId: widget.submittedQuery,
                                  );
                                  ref.read(recentlyPlayedProvider.notifier).add(alt);
                                },
                              )),
                        ],
                      )),
          ),
      ],
    );
  }
}