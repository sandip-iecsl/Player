import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'dart:math';
import '../../domain/entities/song.dart';
import '../providers/audio_provider.dart';
import 'playlist_dialogs.dart';
import '../providers/playlist_provider.dart';
import '../../data/services/audio_service.dart' show audioHandler;
import 'package:palette_generator/palette_generator.dart';
import 'package:audio_service/audio_service.dart';
import '../screens/visualizer_screen.dart';
import '../providers/lyrics_provider.dart';
import 'default_album_art.dart';
import '../providers/torch_provider.dart';
import '../screens/notification_settings_screen.dart';
import '../screens/always_on_display_screen.dart';

class FullPlayer extends ConsumerStatefulWidget {
  final Song currentSong;
  final VoidCallback onClose;

  const FullPlayer({
    super.key,
    required this.currentSong,
    required this.onClose,
  });

  @override
  ConsumerState<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends ConsumerState<FullPlayer> {
  Color? _backgroundColor;
  Timer? _beatTimer;
  double _pulse = 0.0;
  final double _deviceVolume = 1.0;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _updatePalette();
    _startBeatTimer();
  }

  void _startBeatTimer() {
    _beatTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!mounted) return;
      final isPlaying = ref.read(isPlayingProvider).value ?? false;
      final time = DateTime.now().millisecondsSinceEpoch / 1000.0;

      if (isPlaying) {
        // Higher-energy beat simulation for aggressive visualization
        final beatSim = (sin(time * 24.0).abs() * 0.5) + (sin(time * 48.0).abs() * 0.2);
        final baseIntensity = 0.25 + beatSim + _random.nextDouble() * 0.25;
        
        _pulse = (baseIntensity * (_deviceVolume * 0.8 + 0.2)).clamp(0.0, 1.0);
        
        ref.read(torchProvider.notifier).onBeat(_pulse);
      } else {
        if (_pulse > 0.01) {
          _pulse *= 0.8;
          ref.read(torchProvider.notifier).onBeat(_pulse);
        }
      }
    });
  }

  @override
  void didUpdateWidget(FullPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSong.albumArt != widget.currentSong.albumArt) {
      _updatePalette();
    }
  }

  Future<void> _updatePalette() async {
    if (widget.currentSong.albumArt == null) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(widget.currentSong.albumArt!),
      );
      if (mounted) {
        setState(() {
          _backgroundColor = palette.dominantColor?.color;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final currentPosition =
        ref.watch(currentPositionProvider).value ?? Duration.zero;
    final liveDuration = ref.watch(currentDurationProvider).value;
    final audioService = ref.watch(audioServiceProvider);
    final playbackStateStream = ref.watch(audioServiceProvider).playbackState;

    final actualMaxDuration = liveDuration?.inSeconds.toDouble() ??
        widget.currentSong.duration.inSeconds.toDouble();
    final currentValue =
        min(currentPosition.inSeconds.toDouble(), actualMaxDuration);
    final safeValue = max(0.0, currentValue);

    return Scaffold(
      backgroundColor: _backgroundColor ?? Colors.grey.shade900,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              (_backgroundColor ?? Colors.grey.shade900).withOpacity(0.5 + (_pulse * 0.4)),
              Colors.black.withOpacity(0.9 + (_pulse * 0.1)),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down,
                          color: Colors.white, size: 32),
                      onPressed: widget.onClose,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'PLAYING FROM PLAYLIST',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 10,
                                letterSpacing: 1.2),
                          ),
                          Text(
                            widget.currentSong.album ?? 'Aura Player',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.timer_outlined,
                            color: audioHandler.isSleepTimerActive
                                ? const Color(0xFF1DB954)
                                : Colors.white,
                            size: 24,
                          ),
                          onPressed: () => _showSleepTimerDialog(context),
                        ),
                        Consumer(
                          builder: (context, ref, child) {
                            final torch = ref.watch(torchProvider);
                            return IconButton(
                              icon: Icon(
                                torch.isActive ? Icons.flash_on : Icons.flash_off,
                                color: torch.isActive ? Colors.orange : Colors.white,
                              ),
                              onPressed: torch.isAvailable 
                                  ? () => ref.read(torchProvider.notifier).toggleActive()
                                  : null,
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.display_settings_rounded, color: Colors.white),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const AlwaysOnDisplayScreen()),
                            );
                          },
                          tooltip: 'Always On Display',
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                          onPressed: () => _showPlayerMenu(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Album Art
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 30),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.5),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: AlbumArtImage(
                              imageUrl: widget.currentSong.albumArt,
                              fit: BoxFit.cover,
                              borderRadius: BorderRadius.circular(16),
                              title: widget.currentSong.title,
                            ),
                          ),
                        ),
                      ),

                      // Song Info
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.currentSong.title,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.currentSong.artist,
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 16),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                ref
                                        .watch(playlistProvider.notifier)
                                        .isFavorite(widget.currentSong.id)
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: ref
                                        .watch(playlistProvider.notifier)
                                        .isFavorite(widget.currentSong.id)
                                    ? const Color(0xFF1DB954)
                                    : Colors.white,
                                size: 32,
                              ),
                              onPressed: () => ref
                                  .read(playlistProvider.notifier)
                                  .toggleFavorite(widget.currentSong),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline,
                                  color: Colors.white, size: 32),
                              onPressed: () =>
                                  PlaylistDialogs.showAddToPlaylist(
                                      context, ref, widget.currentSong),
                            ),
                            const SizedBox(width: 8),
                            // Visualizer Button
                            IconButton(
                              icon: const Icon(Icons.waves_rounded,
                                  color: Colors.white, size: 30),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => VisualizerScreen(
                                        song: widget.currentSong),
                                  ),
                                );
                              },
                              tooltip: 'Visualizer',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Progress Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: SliderTheme(
                          data: const SliderThemeData(
                            trackHeight: 4,
                            thumbShape:
                                RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape:
                                RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: safeValue,
                            max: max(1.0, actualMaxDuration),
                            onChanged: (value) {
                              audioService
                                  .seek(Duration(seconds: value.toInt()));
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(currentPosition),
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 12),
                            ),
                            Text(
                              _formatDuration(
                                  liveDuration ?? widget.currentSong.duration),
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Controls
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: StreamBuilder<PlaybackState>(
                          stream: playbackStateStream,
                          builder: (context, snapshot) {
                            final state = snapshot.data;
                            final shuffleMode = state?.shuffleMode ??
                                AudioServiceShuffleMode.none;
                            final repeatMode = state?.repeatMode ??
                                AudioServiceRepeatMode.none;

                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Shuffle
                                IconButton(
                                  icon: Icon(
                                    Icons.shuffle_rounded,
                                    color: shuffleMode ==
                                            AudioServiceShuffleMode.all
                                        ? const Color(0xFF1DB954)
                                        : Colors.white,
                                    size: 32,
                                  ),
                                  onPressed: () {
                                    final nextMode = shuffleMode ==
                                            AudioServiceShuffleMode.all
                                        ? AudioServiceShuffleMode.none
                                        : AudioServiceShuffleMode.all;
                                    audioService.setShuffleMode(nextMode);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_previous_rounded,
                                      color: Colors.white, size: 54),
                                  onPressed: () =>
                                      audioService.skipToPrevious(),
                                ),
                                Container(
                                  height: 80,
                                  width: 80,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                        isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.black,
                                        size: 48),
                                    onPressed: () {
                                      if (isPlaying) {
                                        audioService.pause();
                                      } else {
                                        audioService.play();
                                      }
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_next_rounded,
                                      color: Colors.white, size: 54),
                                  onPressed: () => audioService.skipToNext(),
                                ),
                                // Repeat
                                IconButton(
                                  icon: Icon(
                                    repeatMode == AudioServiceRepeatMode.one
                                        ? Icons.repeat_one_rounded
                                        : Icons.repeat_rounded,
                                    color: repeatMode !=
                                            AudioServiceRepeatMode.none
                                        ? const Color(0xFF1DB954)
                                        : Colors.white,
                                    size: 32,
                                  ),
                                  onPressed: () {
                                    AudioServiceRepeatMode nextMode;
                                    if (repeatMode ==
                                        AudioServiceRepeatMode.none) {
                                      nextMode = AudioServiceRepeatMode.all;
                                    } else if (repeatMode ==
                                        AudioServiceRepeatMode.all) {
                                      nextMode = AudioServiceRepeatMode.one;
                                    } else {
                                      nextMode = AudioServiceRepeatMode.none;
                                    }
                                    audioService.setRepeatMode(nextMode);
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Lyrics / Up Next Preview
                      // ── Tabbed Details & Lyrics (Premium UI) ──────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95), // Light background like image
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DefaultTabController(
                            length: 2,
                            initialIndex: 1, // Start on Lyrics as requested
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Tab Bar
                                const TabBar(
                                  labelColor: Colors.black87,
                                  unselectedLabelColor: Colors.black54,
                                  indicatorColor: Colors.black87,
                                  indicatorSize: TabBarIndicatorSize.tab,
                                  tabs: [
                                    Tab(text: 'Details'),
                                    Tab(text: 'Song Lyrics'),
                                  ],
                                ),
                                
                                SizedBox(
                                  height: 400, // Fixed height for scrollable content
                                  child: TabBarView(
                                    children: [
                                      // Tab 1: Details
                                      Padding(
                                        padding: const EdgeInsets.all(20.0),
                                        child: SingleChildScrollView(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              _detailRow('Artist', widget.currentSong.artist),
                                              _detailRow('Album', widget.currentSong.album ?? 'Unknown'),
                                              _detailRow('Duration', _formatDuration(widget.currentSong.duration)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      
                                      // Tab 2: Song Lyrics
                                      Padding(
                                        padding: const EdgeInsets.all(20.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Header Title (Teal Box)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              color: const Color(0xFF00BFA5), // Teal background
                                              child: Text(
                                                '${widget.currentSong.title} Lyrics',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 20),
                                            
                                            // Lyrics Content
                                            Expanded(
                                              child: SingleChildScrollView(
                                                child: Consumer(
                                                  builder: (context, ref, child) {
                                                    final lyricsAsync = ref.watch(lyricsProvider(widget.currentSong));
                                                    return lyricsAsync.when(
                                                      data: (lyrics) {
                                                        if (lyrics == null || lyrics.isEmpty) {
                                                          return const Text(
                                                            'No lyrics found for this track.',
                                                            style: TextStyle(
                                                                color: Colors.black54,
                                                                fontSize: 16,
                                                                fontStyle: FontStyle.italic),
                                                          );
                                                        }
                                                        return Text(
                                                          lyrics,
                                                          style: const TextStyle(
                                                              color: Colors.black87,
                                                              fontSize: 18,
                                                              height: 1.6,
                                                              fontWeight: FontWeight.w400),
                                                        );
                                                      },
                                                      loading: () => const Center(
                                                        child: CircularProgressIndicator(color: Color(0xFF00BFA5)),
                                                      ),
                                                      error: (err, stack) => const Text(
                                                        'Failed to load lyrics.',
                                                        style: TextStyle(color: Colors.red),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Bottom Icons
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.queue_music_rounded,
                                  color: Colors.white70, size: 28),
                              onPressed: () {
                                // TODO: Show Queue
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Queue feature coming soon!'),
                                      duration: Duration(seconds: 1)),
                                );
                              },
                              tooltip: 'Queue',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) duration = Duration.zero;
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _showSleepTimerDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Sleep Timer',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (audioHandler.isSleepTimerActive)
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1DB954).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1DB954)),
                    ),
                    child: const Column(
                      children: [
                        Text(
                          'Sleep timer is active',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Timer will stop playback automatically',
                          style: TextStyle(
                            color: Color(0xFF1DB954),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    children: [
                      const Text(
                        'Set sleep timer',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [5, 10, 15, 30, 45, 60].map((minutes) {
                          return ElevatedButton(
                            onPressed: () {
                              audioHandler.setSleepTimer(Duration(minutes: minutes));
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1DB954),
                              foregroundColor: Colors.white,
                            ),
                            child: Text('${minutes}m'),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPlayerMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Player Options',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.notifications_active, color: Colors.white),
              title: const Text(
                'Notification Controls',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Customize notification style and animations',
                style: TextStyle(color: Colors.grey),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationSettingsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.equalizer, color: Colors.white),
              title: const Text(
                'Audio Equalizer',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Coming soon',
                style: TextStyle(color: Colors.grey),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Equalizer coming soon!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text(
                'Share Song',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Sharing "${widget.currentSong.title}"'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}