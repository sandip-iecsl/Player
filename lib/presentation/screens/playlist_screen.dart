import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/audio_service.dart'; // PlaybackContext
import '../../domain/entities/song.dart';
import '../providers/audio_provider.dart';
import '../providers/history_provider.dart';
import '../providers/playlist_provider.dart';
import '../widgets/playlist_dialogs.dart';

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
  // De-duplicate once at state level — stable across rebuilds
  late final List<Song> _songs;
  bool _isShuffleOn = false;

  @override
  void initState() {
    super.initState();
    final seen = <String>{};
    _songs = widget.songs.where((s) => seen.add(s.id)).toList();
  }

  // ── Play all ─────────────────────────────────────────────────────────────

  Future<void> _playAll({int startIndex = 0}) async {
    if (_songs.isEmpty) return;
    final audio = ref.read(audioServiceProvider);

    // Apply shuffle first if active
    List<Song> queue = List.from(_songs);
    if (_isShuffleOn) {
      queue.shuffle();
      startIndex = 0; // shuffled — always start from new index 0
    }

    await audio.loadQueue(
      queue,
      startIndex: startIndex,
      context: PlaybackContext.playlist, // → stops at end, no autoplay
    );
    ref.read(recentlyPlayedProvider.notifier).add(queue[startIndex]);
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
    // If nothing loaded yet → load and play from beginning
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
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: Colors.black,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.grey.shade800, Colors.black],
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
                            color: Colors.black.withOpacity(0.5),
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
                                color: Colors.grey.shade800,
                                child: const Icon(Icons.music_note, size: 60, color: Colors.white),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.playlistTitle,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_songs.length} songs',
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
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
                  const Icon(Icons.favorite_border, color: Colors.white, size: 28),
                  const SizedBox(width: 24),
                  const Icon(Icons.more_vert, color: Colors.grey, size: 28),
                  const Spacer(),

                  // ── Shuffle button (active = green) ──────────────────────
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: _isShuffleOn ? Colors.green : Colors.white54,
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
                      backgroundColor: Colors.green,
                      radius: 28,
                      child: Icon(
                        isThisPlaylistPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.black,
                        size: 32,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Song list ─────────────────────────────────────────────────────
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= _songs.length) return null;
                final song = _songs[index];
                final isCurrentlyPlaying = currentSong?.id == song.id && isPlaying;

                return InkWell(
                  onTap: () => _playAll(startIndex: index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        // Album art
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: song.albumArt != null
                              ? Image.network(song.albumArt!, width: 48, height: 48, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(width: 48, height: 48, color: Colors.grey.shade800))
                              : Container(width: 48, height: 48, color: Colors.grey.shade800,
                                  child: const Icon(Icons.music_note, color: Colors.white54)),
                        ),
                        const SizedBox(width: 12),
                        // Title + artist
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                style: TextStyle(
                                  color: isCurrentlyPlaying ? Colors.green : Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(song.artist,
                                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
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
                          icon: const Icon(Icons.more_vert, color: Colors.grey),
                          onPressed: () => _showSongOptions(context, song),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: _songs.length,
            ),
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
          color: Colors.green,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  double _sin(double x) => (x - x.floor()) < 0.5
      ? 2 * (x - x.floor())
      : 2 * (1 - (x - x.floor()));
}
