import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';
import '../../data/services/audio_service.dart'; // PlaybackContext
import '../providers/audio_provider.dart';
import '../providers/music_provider.dart';
import '../providers/music_data_providers.dart';
import '../providers/history_provider.dart';
import '../widgets/playlist_dialogs.dart';

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
  
  // Pagination state
  List<Song> _allResults = [];
  bool _isLoadingMore = false;
  bool _hasMoreResults = true;
  int _currentPage = 1;
  static const int _pageSize = 20;

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
        });
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

  /// Called when the user presses Enter or taps Search.
  void _onSubmit(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    ref.read(searchHistoryProvider.notifier).add(q);
    _resetPagination(); // Reset pagination for new search
    setState(() => _submittedQuery = q);
    _focusNode.unfocus();
  }

  void _onHistoryTap(String query) {
    _searchController.text = query;
    _resetPagination(); // Reset pagination for new search
    setState(() {
      _liveQuery = query;
      _submittedQuery = query;
    });
    _focusNode.unfocus();
  }

  void _clearSearch() {
    _searchController.clear();
    _resetPagination(); // Reset pagination when clearing
    setState(() {
      _liveQuery = '';
      _submittedQuery = '';
    });
  }

  /// Called by MainScreen when this tab is deselected — clears state.
  void clearState() {
    _searchController.clear();
    _resetPagination(); // Reset pagination when clearing
    if (mounted) setState(() { _liveQuery = ''; _submittedQuery = ''; });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final searchHistory = ref.watch(searchHistoryProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Search',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                onChanged: (val) {
                  setState(() => _liveQuery = val);
                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                  _debounce = Timer(const Duration(milliseconds: 500), () {
                    final q = val.trim();
                    _resetPagination(); // Reset pagination for new search
                    setState(() => _submittedQuery = q);
                  });
                },
                onSubmitted: _onSubmit,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'What do you want to listen to?',
                  hintStyle: const TextStyle(color: Colors.black54),
                  prefixIcon: const Icon(Icons.search, color: Colors.black54),
                  suffixIcon: _liveQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, color: Colors.black54),
                          onPressed: _clearSearch,
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: _submittedQuery.isEmpty
                  ? _buildHistory(searchHistory)
                  : _buildResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory(List<String> history) {
    if (history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, color: Colors.grey, size: 60),
            SizedBox(height: 16),
            Text(
              'Search for songs, artists, albums',
              style: TextStyle(color: Colors.grey, fontSize: 16),
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
            const Text(
              'Recent searches',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
              child: const Text('Clear all', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...history.map((query) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.history, color: Colors.grey),
          title: Text(query, style: const TextStyle(color: Colors.white)),
          trailing: IconButton(
            icon: const Icon(Icons.close, color: Colors.grey, size: 18),
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
              return const Center(
                child: Text('No results found', style: TextStyle(color: Colors.grey, fontSize: 16)),
              );
            }

            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: displayResults.length + (_isLoadingMore ? 1 : (_hasMoreResults ? 1 : 0)),
              itemBuilder: (context, index) {
                // Show loading indicator at the end
                if (index == displayResults.length && _isLoadingMore) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFF1DB954)),
                    ),
                  );
                }
                
                // Show "Load More" button if has more results and not currently loading
                if (index == displayResults.length && _hasMoreResults && !_isLoadingMore) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: ElevatedButton.icon(
                        onPressed: _loadMoreResults,
                        icon: const Icon(Icons.add),
                        label: Text('Load More (Page $_currentPage)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ),
                  );
                }
                
                final song = displayResults[index];
                final isPlaying = ref.watch(currentSongProvider).valueOrNull?.id == song.id;
                final isTrending = matchedTrending.any((t) => t.id == song.id);

                return ListTile(
                  leading: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: song.albumArt != null
                            ? Image.network(song.albumArt!, width: 50, height: 50, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(width: 50, height: 50, color: Colors.grey[800], child: const Icon(Icons.music_note, color: Colors.white)))
                            : Container(width: 50, height: 50, color: Colors.grey[800], child: const Icon(Icons.music_note, color: Colors.white)),
                      ),
                      if (isTrending)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                            child: const Icon(Icons.trending_up, color: Colors.black, size: 10),
                          ),
                        ),
                    ],
                  ),
                  title: Text(
                    song.title,
                    style: TextStyle(
                      color: isPlaying ? const Color(0xFF1DB954) : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    isTrending ? 'Trending • ${song.artist}' : song.artist,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  trailing: isPlaying
                      ? const Icon(Icons.equalizer_rounded, color: Color(0xFF1DB954))
                      : IconButton(
                          icon: const Icon(Icons.more_vert, color: Colors.grey),
                          onPressed: () => PlaylistDialogs.showSongOptions(context, ref, song),
                        ),
                  onTap: () {
                    ref.read(audioServiceProvider).loadQueue(
                      [song],
                      startIndex: 0,
                      context: PlaybackContext.search, // → autoplay radio after queue ends
                    );
                    ref.read(recentlyPlayedProvider.notifier).add(song);
                    if (_submittedQuery.isNotEmpty) {
                      ref.read(searchHistoryProvider.notifier).add(_submittedQuery);
                    }
                  },
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954))),
          error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
        );
      },
    );
  }
}
