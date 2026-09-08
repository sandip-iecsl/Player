import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../data/services/audio_service.dart'; // PlaybackContext
import '../../data/services/offline_storage_service.dart';
import '../../domain/entities/song.dart';
import '../providers/audio_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/history_provider.dart';
import '../providers/music_data_providers.dart';
import '../widgets/playlist_dialogs.dart';
import '../../core/constants/app_colors.dart';

class PlaylistScreen extends ConsumerStatefulWidget {
  final String? playlistId;
  final String playlistTitle;
  final String? coverUrl;
  final List<Song> songs;

  const PlaylistScreen({
    super.key,
    this.playlistId,
    required this.playlistTitle,
    this.coverUrl,
    required this.songs,
  });

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  // Dynamic list of songs for pagination support
  final List<Song> _songs = [];
  bool _isShuffleOn = false;

  // Pagination state
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMoreResults = true;
  int _currentPage = 1;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    final seen = <String>{};
    _songs.addAll(widget.songs.where((s) => seen.add(s.id)));
    
    if (widget.playlistId != null) {
      _scrollController.addListener(_onScroll);
      _currentPage = (_songs.length / _pageSize).ceil();
      if (_songs.length < 20) {
        _hasMoreResults = false;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    
    final position = _scrollController.position;
    final threshold = position.maxScrollExtent - 200;
    
    if (position.pixels >= threshold) {
      if (!_isLoadingMore && _hasMoreResults) {
        _loadMoreTracks();
      }
    }
  }

  Future<void> _loadMoreTracks() async {
    if (_isLoadingMore || !_hasMoreResults || widget.playlistId == null) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      final spotify = ref.read(spotifyServiceProvider);
      final hybrid  = ref.read(hybridSearchServiceProvider);
      
      debugPrint('[PlaylistScreen] 🔄 Loading page $_currentPage for playlist: ${widget.playlistId}');
      
      final tracks = await spotify.getPlaylistTracks(
        widget.playlistId!, 
        limit: 50, 
        offset: _currentPage * 50,
      );
      
      if (tracks.isEmpty) {
        if (mounted) {
          setState(() {
            _hasMoreResults = false;
            _isLoadingMore = false;
          });
        }
        return;
      }
      
      // Resolve these tracks to playable songs
      final resolvedSongs = <Song>[];
      for (final t in tracks) {
        final results = await hybrid.searchSongs('${t.title} ${t.artist}', limit: 1);
        if (results.isNotEmpty) {
          resolvedSongs.add(results.first);
        }
        if (resolvedSongs.length >= 20) break;
      }
      
      if (mounted) {
        setState(() {
          if (resolvedSongs.isEmpty) {
            _hasMoreResults = false;
          } else {
            final existingIds = _songs.map((s) => s.id).toSet();
            final uniqueNewSongs = resolvedSongs.where((s) => !existingIds.contains(s.id)).toList();
            
            if (uniqueNewSongs.isEmpty) {
              _hasMoreResults = false;
            } else {
              _songs.addAll(uniqueNewSongs);
              _currentPage++;
              
              // Sync with active queue if user is playing from this playlist
              final audio = ref.read(audioServiceProvider);
              if (audio.currentContext == PlaybackContext.playlist && audio.currentContextId == widget.playlistId) {
                audio.appendSongs(uniqueNewSongs);
              }
            }
          }
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('[PlaylistScreen] ❌ Error loading more tracks: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  // ── Play all (Sequential vs Shuffle Queue) ─────────────────────────────────

  Future<void> _playAll({int startIndex = 0, Song? targetSong}) async {
    if (_songs.isEmpty) return;
    final audio = ref.read(audioServiceProvider);
    final isOnline = ref.read(connectivityProvider).valueOrNull ?? true;

    // Determine playable candidate songs depending on offline/online state
    List<Song> playablePool;
    if (!isOnline) {
      playablePool = _songs.where((s) => 
        OfflineStorageService.isDownloaded(s.id) || 
        (s.previewUrl != null && !s.previewUrl!.startsWith('http'))
      ).toList();

      if (playablePool.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.wifi_off_rounded, color: Colors.orangeAccent, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('No downloaded songs available in this playlist for offline playback.'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF252530),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        return;
      }
    } else {
      playablePool = List.from(_songs);
    }

    // Determine starting index in the playable pool
    int effectiveStartIndex = startIndex;
    if (targetSong != null) {
      final foundIdx = playablePool.indexWhere((s) => s.id == targetSong.id);
      effectiveStartIndex = foundIdx >= 0 ? foundIdx : 0;
    } else {
      effectiveStartIndex = effectiveStartIndex.clamp(0, playablePool.length - 1);
    }

    List<Song> queue = List.from(playablePool);

    if (_isShuffleOn) {
      final startingSong = queue[effectiveStartIndex];
      queue.removeAt(effectiveStartIndex);
      queue.shuffle();
      queue.insert(0, startingSong);
      effectiveStartIndex = 0; // Tapped track is now index 0, followed by randomized items
      await audio.setShuffleMode(AudioServiceShuffleMode.all);
    } else {
      await audio.setShuffleMode(AudioServiceShuffleMode.none);
    }

    await audio.loadQueue(
      queue,
      startIndex: effectiveStartIndex,
      context: PlaybackContext.playlist, // Bound to playlist, sequential progression
      contextId: widget.playlistId,
    );

    if (queue.isNotEmpty && effectiveStartIndex < queue.length) {
      ref.read(recentlyPlayedProvider.notifier).add(queue[effectiveStartIndex]);
    }
  }

  // ── Shuffle toggle ────────────────────────────────────────────────────────

  Future<void> _toggleShuffle() async {
    setState(() => _isShuffleOn = !_isShuffleOn);
    final audio = ref.read(audioServiceProvider);
    await audio.setShuffleMode(
      _isShuffleOn
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );
  }

  // ── Play/pause toggle ──────────────────────────────────────────────────────

  Future<void> _onPlayPauseTap(bool isPlaying) async {
    final audio = ref.read(audioServiceProvider);
    final current = ref.read(currentSongProvider).valueOrNull;
    if (current == null) {
      await _playAll();
      return;
    }
    if (isPlaying) {
      await audio.pause();
    } else {
      await audio.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(currentSongProvider).valueOrNull;
    final isPlayingAsync = ref.watch(isPlayingProvider);
    final isPlaying = isPlayingAsync.valueOrNull ?? false;

    // The play button is "playing THIS playlist" if the current song is in it
    final isThisPlaylistPlaying =
        isPlaying && _songs.any((s) => s.id == currentSong?.id);

    return Scaffold(
      backgroundColor: AppColors.deepSpaceBlack,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ── Header ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppColors.deepSpaceBlack,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.deepSpaceBlackLight, AppColors.deepSpaceBlack],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 50),
                    Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.deepSpaceBlack.withOpacity(0.5),
                            offset: const Offset(0, 10),
                            blurRadius: 20,
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: widget.coverUrl != null
                            ? Image.network(widget.coverUrl!, width: 150, height: 150, fit: BoxFit.cover)
                            : Container(
                                width: 150,
                                height: 150,
                                color: AppColors.deepSpaceBlackLighter,
                                child: Icon(Icons.music_note, size: 60, color: AppColors.textPrimary),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.playlistTitle,
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_songs.length} songs',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Controls row ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.favorite_border, color: AppColors.textPrimary, size: 28),
                  const SizedBox(width: 24),
                  Icon(Icons.more_vert, color: AppColors.textSecondary, size: 28),
                  const Spacer(),

                  // ── Shuffle button (active = green) ──────────────────────
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: _isShuffleOn ? AppColors.neonPink : AppColors.divider,
                      size: 28,
                    ),
                    onPressed: _toggleShuffle,
                    tooltip: 'Shuffle',
                  ),
                  const SizedBox(width: 8),

                  // ── Play/Pause button (reacts to isPlayingProvider) ───────
                  GestureDetector(
                    onTap: () => _onPlayPauseTap(isThisPlaylistPlaying),
                    child: CircleAvatar(
                      backgroundColor: AppColors.neonPink,
                      radius: 28,
                      child: Icon(
                        isThisPlaylistPlaying ? Icons.pause : Icons.play_arrow,
                        color: AppColors.deepSpaceBlack,
                        size: 32,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Song list with Dynamic Offline Filtering & Badges ───────────
          ValueListenableBuilder(
            valueListenable: Hive.box('offline_songs').listenable(),
            builder: (context, Box box, _) {
              final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == _songs.length && _hasMoreResults && widget.playlistId != null) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.neonPink,
                            strokeWidth: 2.5,
                          ),
                        ),
                      );
                    }
                    if (index >= _songs.length) return null;
                    final song = _songs[index];
                    final isCurrentlyPlaying = currentSong?.id == song.id && isPlaying;
                    final isDownloaded = OfflineStorageService.isDownloaded(song.id) ||
                        (song.previewUrl != null && !song.previewUrl!.startsWith('http'));
                    final isPlayable = isOnline || isDownloaded;

                    return Opacity(
                      opacity: isPlayable ? 1.0 : 0.45,
                      child: InkWell(
                        onTap: () {
                          if (isPlayable) {
                            _playAll(targetSong: song);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.cloud_off_rounded, color: Colors.orangeAccent, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text('"${song.title}" is online-only. Connect to internet or download for offline playback.'),
                                    ),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF252530),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              // Album art
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: song.albumArt != null
                                        ? Image.network(
                                            song.albumArt!,
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              width: 48,
                                              height: 48,
                                              color: AppColors.deepSpaceBlackLighter,
                                              child: Icon(Icons.music_note, color: AppColors.textSecondary),
                                            ),
                                          )
                                        : Container(
                                            width: 48,
                                            height: 48,
                                            color: AppColors.deepSpaceBlackLighter,
                                            child: Icon(Icons.music_note, color: AppColors.textSecondary),
                                          ),
                                  ),
                                  if (!isPlayable)
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 20),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              // Title + artist + offline badge
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            song.title,
                                            style: TextStyle(
                                              color: isCurrentlyPlaying ? AppColors.neonPink : AppColors.textPrimary,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isDownloaded) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: Colors.greenAccent.withAlpha(35),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.greenAccent.withAlpha(90), width: 0.8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.download_done_rounded, color: Colors.greenAccent, size: 10),
                                                SizedBox(width: 3),
                                                Text(
                                                  'OFFLINE',
                                                  style: TextStyle(
                                                    color: Colors.greenAccent,
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ] else if (!isOnline) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: Colors.white10,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'ONLINE ONLY',
                                              style: TextStyle(
                                                color: Colors.white54,
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      song.artist,
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              // Equalizer indicator if this song is playing
                              if (isCurrentlyPlaying)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: _MiniEqualizer(),
                                ),
                              // Options
                              IconButton(
                                icon: Icon(Icons.more_vert, color: AppColors.textSecondary),
                                onPressed: () => _showSongOptions(context, song),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: _songs.length + (_hasMoreResults && widget.playlistId != null ? 1 : 0),
                ),
              );
            },
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  void _showSongOptions(BuildContext context, Song song) {
    PlaylistDialogs.showSongOptions(
      context, 
      ref, 
      song, 
      playlistId: widget.playlistId,
    );
  }
}

// ── Animated mini equalizer bars ──────────────────────────────────────────────
// Shown next to the currently playing song in the playlist

class _MiniEqualizer extends StatefulWidget {
  const _MiniEqualizer();

  @override
  State<_MiniEqualizer> createState() => _MiniEqualizerState();
}

class _MiniEqualizerState extends State<_MiniEqualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 2.4s full cycle = slow, organic wave movement
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = _controller.value * 2 * 3.14159265;
        // Each bar uses a sine wave with different phase & amplitude
        final h1 = 6 + 10 * ((1 + _sin(t * 1.1)) / 2);
        final h2 = 6 + 10 * ((1 + _sin(t * 1.7 + 1.0)) / 2);
        final h3 = 6 + 10 * ((1 + _sin(t * 1.3 + 2.1)) / 2);

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(h1),
            const SizedBox(width: 2),
            _bar(h2),
            const SizedBox(width: 2),
            _bar(h3),
          ],
        );
      },
    );
  }

  Widget _bar(double height) => Container(
        width: 3,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.neonPink,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  double _sin(double x) => (x - x.floor()) < 0.5
      ? 2 * (x - x.floor())
      : 2 * (1 - (x - x.floor()));
}