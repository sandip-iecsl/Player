import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;
import '../../domain/entities/song.dart';
import '../providers/audio_provider.dart';
import 'playlist_dialogs.dart';
import '../providers/playlist_provider.dart';
import '../../data/services/audio_service.dart' show audioHandler, PlaybackContext, AudioServiceHandler;
import 'package:palette_generator/palette_generator.dart';
import 'package:audio_service/audio_service.dart';
import '../screens/visualizer_screen.dart';
import '../providers/lyrics_provider.dart';
import '../../data/services/offline_storage_service.dart';
import 'default_album_art.dart';
import '../providers/torch_provider.dart';
import 'theme_selection_dialog.dart';
import '../providers/music_data_providers.dart';
import '../providers/history_provider.dart';
import 'neumorphic_container.dart';
import '../../core/constants/app_colors.dart';
import 'synchronized_lyrics_widget.dart';
import 'package:flutter/services.dart';
import '../providers/theme_provider.dart';

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
  double? _dragValue;
  double _playButtonScale = 1.0;
  bool _isDownloadingOffline = false;
  double _downloadProgress = 0.0;

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
    final themeMode = ref.watch(themeModeProvider);
    ref.watch(themeColorProvider);
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: themeMode == ThemeMode.light ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: _backgroundColor ?? AppColors.deepSpaceBlack,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: widget.currentSong.albumArt != null
                        ? Image.network(
                            widget.currentSong.albumArt!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 40.0, sigmaY: 40.0),
                      child: Container(
                        color: Colors.black.withOpacity(0.45),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            (_backgroundColor ?? AppColors.deepSpaceBlack).withOpacity(0.35),
                            AppColors.deepSpaceBlack.withOpacity(0.92),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
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
                      icon: Icon(Icons.keyboard_arrow_down,
                          color: AppColors.textPrimary, size: 32),
                      onPressed: widget.onClose,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'PLAYING FROM PLAYLIST',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10,
                                letterSpacing: 1.2),
                          ),
                          Text(
                            widget.currentSong.album ?? 'Aura Player',
                            style: TextStyle(
                                color: AppColors.textPrimary,
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
                                ? AppColors.neonPink
                                : AppColors.textPrimary,
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
                                color: torch.isActive ? Colors.orange : AppColors.textPrimary,
                              ),
                              onPressed: torch.isAvailable 
                                  ? () => ref.read(torchProvider.notifier).toggleActive()
                                  : null,
                            );
                          },
                        ),
                        // OFFLINE DOWNLOAD BUTTON
                        ValueListenableBuilder(
                          valueListenable: Hive.box('offline_songs').listenable(),
                          builder: (context, Box box, _) {
                            final isDownloaded = box.containsKey(widget.currentSong.id);

                            return IconButton(
                              icon: _isDownloadingOffline
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: AppColors.neonPink,
                                        strokeWidth: 2.5,
                                        value: _downloadProgress > 0 ? _downloadProgress : null,
                                      ),
                                    )
                                  : Icon(
                                      isDownloaded ? Icons.offline_pin_rounded : Icons.download_for_offline_outlined,
                                      color: isDownloaded ? AppColors.neonPink : AppColors.textPrimary,
                                      size: 24,
                                    ),
                              tooltip: isDownloaded ? 'Remove from Offline' : 'Download for Offline',
                              onPressed: _isDownloadingOffline
                                  ? null
                                  : () async {
                                       if (isDownloaded) {
                                         await OfflineStorageService.removeSong(widget.currentSong.id);
                                         if (mounted && context.mounted) {
                                           ScaffoldMessenger.of(context).showSnackBar(
                                             SnackBar(
                                               content: Row(
                                                 children: [
                                                   Container(
                                                     padding: const EdgeInsets.all(4),
                                                     decoration: BoxDecoration(
                                                       color: Colors.white.withValues(alpha: 0.1),
                                                       shape: BoxShape.circle,
                                                     ),
                                                     child: const Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 16),
                                                   ),
                                                   const SizedBox(width: 10),
                                                   Expanded(
                                                     child: Text(
                                                       'Removed "${widget.currentSong.title}" from offline storage',
                                                       style: const TextStyle(
                                                         color: Colors.white,
                                                         fontWeight: FontWeight.w600,
                                                         fontSize: 13,
                                                       ),
                                                     ),
                                                   ),
                                                 ],
                                               ),
                                               backgroundColor: const Color(0xFF1E1E26),
                                               behavior: SnackBarBehavior.floating,
                                               elevation: 8,
                                               shape: RoundedRectangleBorder(
                                                 borderRadius: BorderRadius.circular(14),
                                                 side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                                               ),
                                               margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                                               duration: const Duration(seconds: 2),
                                             ),
                                           );
                                         }
                                       } else {
                                         setState(() {
                                           _isDownloadingOffline = true;
                                           _downloadProgress = 0.0;
                                         });
                                         try {
                                           await OfflineStorageService.downloadSong(widget.currentSong, (progress) {
                                             if (mounted) {
                                               setState(() => _downloadProgress = progress);
                                             }
                                           });
                                           if (mounted && context.mounted) {
                                             ScaffoldMessenger.of(context).showSnackBar(
                                               SnackBar(
                                                 content: Row(
                                                   children: [
                                                     Container(
                                                       padding: const EdgeInsets.all(4),
                                                       decoration: BoxDecoration(
                                                         color: Colors.greenAccent.withValues(alpha: 0.2),
                                                         shape: BoxShape.circle,
                                                       ),
                                                       child: const Icon(Icons.check_rounded, color: Colors.greenAccent, size: 16),
                                                     ),
                                                     const SizedBox(width: 10),
                                                     Expanded(
                                                       child: Text(
                                                         'Downloaded "${widget.currentSong.title}" for offline playback!',
                                                         style: const TextStyle(
                                                           color: Colors.white,
                                                           fontWeight: FontWeight.w600,
                                                           fontSize: 13,
                                                         ),
                                                       ),
                                                     ),
                                                   ],
                                                 ),
                                                 backgroundColor: const Color(0xFF1E1E26),
                                                 behavior: SnackBarBehavior.floating,
                                                 elevation: 8,
                                                 shape: RoundedRectangleBorder(
                                                   borderRadius: BorderRadius.circular(14),
                                                   side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                                                 ),
                                                 margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                                                 duration: const Duration(seconds: 3),
                                               ),
                                             );
                                           }
                                         } catch (e) {
                                           if (mounted && context.mounted) {
                                             ScaffoldMessenger.of(context).showSnackBar(
                                               SnackBar(
                                                 content: Row(
                                                   children: [
                                                     Container(
                                                       padding: const EdgeInsets.all(4),
                                                       decoration: BoxDecoration(
                                                         color: Colors.redAccent.withValues(alpha: 0.2),
                                                         shape: BoxShape.circle,
                                                       ),
                                                       child: const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                                                     ),
                                                     const SizedBox(width: 10),
                                                     Expanded(
                                                       child: Text(
                                                         'Download failed: $e',
                                                         style: const TextStyle(
                                                           color: Colors.white,
                                                           fontWeight: FontWeight.w600,
                                                           fontSize: 13,
                                                         ),
                                                       ),
                                                     ),
                                                   ],
                                                 ),
                                                 backgroundColor: const Color(0xFF1E1E26),
                                                 behavior: SnackBarBehavior.floating,
                                                 elevation: 8,
                                                 shape: RoundedRectangleBorder(
                                                   borderRadius: BorderRadius.circular(14),
                                                   side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                                                 ),
                                                 margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                                                 duration: const Duration(seconds: 3),
                                               ),
                                             );
                                           }
                                         } finally {
                                          if (mounted) {
                                            setState(() {
                                              _isDownloadingOffline = false;
                                              _downloadProgress = 0.0;
                                            });
                                          }
                                        }
                                      }
                                    },
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.more_vert, color: AppColors.textPrimary),
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
                          child: Hero(
                            tag: 'album_art_${widget.currentSong.id}',
                            child: NeumorphicContainer(
                              borderRadius: BorderRadius.circular(24),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: AlbumArtImage(
                                  imageUrl: widget.currentSong.albumArt,
                                  fit: BoxFit.cover,
                                  borderRadius: BorderRadius.circular(24),
                                  title: widget.currentSong.title,
                                ),
                              ),
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
                                    style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        shadows: [
                                          Shadow(
                                            color: AppColors.neonPink.withOpacity(0.55),
                                            offset: const Offset(0, 0),
                                            blurRadius: 10,
                                          ),
                                        ]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.currentSong.artist,
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500),
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
                                    ? AppColors.neonPink
                                    : AppColors.textPrimary,
                                size: 32,
                              ),
                              onPressed: () => ref
                                  .read(playlistProvider.notifier)
                                  .toggleFavorite(widget.currentSong),
                            ),
                            const SizedBox(width: 8),
                             IconButton(
                              icon: Icon(Icons.add_circle_outline,
                                  color: AppColors.textPrimary, size: 32),
                              onPressed: () =>
                                  PlaylistDialogs.showAddToPlaylist(
                                      context, ref, widget.currentSong),
                            ),
                            const SizedBox(width: 8),
                            // Visualizer Button
                            IconButton(
                              icon: Icon(Icons.waves_rounded,
                                  color: AppColors.textPrimary, size: 30),
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
                          data: SliderThemeData(
                            trackHeight: 4,
                            thumbShape: GlowingRoundSliderThumbShape(
                              enabledThumbRadius: 7,
                              glowColor: AppColors.neonPink,
                              glowRadius: 10,
                            ),
                            overlayShape:
                                const RoundSliderOverlayShape(overlayRadius: 14),
                            activeTrackColor: AppColors.neonPink,
                            inactiveTrackColor: AppColors.divider.withOpacity(0.3),
                            thumbColor: AppColors.neonPink,
                            overlayColor: AppColors.neonPink.withOpacity(0.12),
                          ),
                          child: Slider(
                            value: _dragValue ?? safeValue,
                            max: max(1.0, actualMaxDuration),
                            onChangeStart: (value) {
                              setState(() {
                                _dragValue = value;
                              });
                            },
                            onChanged: (value) {
                              setState(() {
                                _dragValue = value;
                              });
                            },
                            onChangeEnd: (value) {
                              audioService
                                  .seek(Duration(seconds: value.toInt()));
                              setState(() {
                                _dragValue = null;
                              });
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
                              _formatDuration(_dragValue != null
                                  ? Duration(seconds: _dragValue!.toInt())
                                  : currentPosition),
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12),
                            ),
                            Text(
                              _formatDuration(
                                  liveDuration ?? widget.currentSong.duration),
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

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
                                        ? AppColors.neonPink
                                        : AppColors.textSecondary,
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
                                  icon: Icon(Icons.skip_previous_rounded,
                                      color: AppColors.textPrimary, size: 54),
                                  onPressed: () =>
                                      audioService.skipToPrevious(),
                                ),
                                GestureDetector(
                                  onTapDown: (_) => setState(() => _playButtonScale = 0.85),
                                  onTapUp: (_) => setState(() => _playButtonScale = 1.0),
                                  onTapCancel: () => setState(() => _playButtonScale = 1.0),
                                  child: AnimatedScale(
                                    scale: _playButtonScale * (isPlaying ? 1.08 : 1.0),
                                    duration: const Duration(milliseconds: 150),
                                    curve: Curves.bounceOut,
                                    child: NeumorphicContainer(
                                      height: 80,
                                      width: 80,
                                      shape: BoxShape.circle,
                                      color: AppColors.neonPink,
                                      child: IconButton(
                                        icon: Icon(
                                            isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            color: AppColors.deepSpaceBlack,
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
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.skip_next_rounded,
                                      color: AppColors.textPrimary, size: 54),
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
                                        ? AppColors.neonPink
                                        : AppColors.textSecondary,
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
                            color: AppColors.deepSpaceBlackLight, // Dark theme background
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.neonPink.withOpacity(0.15),
                              width: 1,
                            ),
                          ),
                          child: DefaultTabController(
                            length: 2,
                            initialIndex: 1, // Start on Lyrics as requested
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Tab Bar
                                TabBar(
                                  labelColor: AppColors.neonPink,
                                  unselectedLabelColor: AppColors.textSecondary,
                                  indicatorColor: AppColors.neonPink,
                                  indicatorSize: TabBarIndicatorSize.tab,
                                  tabs: const [
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
                                              _detailRow('Song Title', widget.currentSong.title),
                                              _detailRow('Artist', widget.currentSong.artist),
                                              _detailRow('Album', widget.currentSong.album ?? 'Single / Unknown'),
                                              _detailRow('Duration', _formatDuration(widget.currentSong.duration)),
                                              _detailRow('Audio Codec', 'MP3 (MPEG-1 Audio Layer III)'),
                                              _detailRow('Bitrate', '320 kbps (High Quality)'),
                                              _detailRow('Sample Rate', '44.1 kHz'),
                                              _detailRow('Channels', 'Stereo (2.0)'),
                                              _detailRow('Source', widget.currentSong.previewUrl != null && widget.currentSong.previewUrl!.contains('jiosaavn') ? 'JioSaavn CDN' : 'High Quality Stream'),
                                              Builder(
                                                builder: (context) {
                                                  final int durationSec = widget.currentSong.duration.inSeconds;
                                                  final double estSizeMb = (durationSec * 320) / (8 * 1024);
                                                  final String estSizeStr = durationSec > 0 ? '${estSizeMb.toStringAsFixed(2)} MB' : 'Unknown';
                                                  return _detailRow('Est. Size', estSizeStr);
                                                },
                                              ),
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
                                            // Header Title
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 12.0),
                                              child: Text(
                                                'Lyrics',
                                                style: TextStyle(
                                                  color: AppColors.neonPink,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 20),
                                            
                                            // Lyrics Content
                                            Expanded(
                                              child: Consumer(
                                                builder: (context, ref, child) {
                                                  final lyricsAsync = ref.watch(lyricsProvider(widget.currentSong));
                                                  return lyricsAsync.when(
                                                    data: (lyricsData) {
                                                      if (lyricsData == null || lyricsData.isEmpty) {
                                                        return Center(
                                                          child: Text(
                                                            'No lyrics found for this track.',
                                                            style: TextStyle(
                                                                color: AppColors.textSecondary,
                                                                fontSize: 16,
                                                                fontStyle: FontStyle.italic),
                                                          ),
                                                        );
                                                      }
                                                      return SynchronizedLyricsWidget(
                                                        lyricsData: lyricsData,
                                                        positionStream: ref.read(audioServiceProvider).positionStream,
                                                      );
                                                    },
                                                    loading: () => Center(
                                                      child: CircularProgressIndicator(color: AppColors.neonPink),
                                                    ),
                                                    error: (err, stack) => const Center(
                                                      child: Text(
                                                        'Failed to load lyrics.',
                                                        style: TextStyle(color: Colors.red),
                                                      ),
                                                    ),
                                                  );
                                                },
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

                      // ── More by this Artist Related Songs ──────────────────────
                      Consumer(
                        builder: (context, ref, child) {
                          final artists = widget.currentSong.artist
                              .split(RegExp(r'[,&]'))
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList();
                          
                          final joinedArtistsKey = artists.join('|');
                          final relatedSongsAsync =
                              ref.watch(multipleArtistsTopTracksProvider(joinedArtistsKey));

                          return relatedSongsAsync.when(
                            data: (songs) {
                              // Filter out current song
                              final filteredSongs = songs
                                  .where((s) => s.id != widget.currentSong.id)
                                  .toList();

                              if (filteredSongs.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              // Limit to top 20 trending songs
                              final topSongs = filteredSongs.take(20).toList();
                              
                              final displayArtistText = artists.length > 2 
                                  ? '${artists.take(2).join(' & ')} & more'
                                  : artists.join(' & ');

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Top Tracks by $displayArtistText',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      height: 204,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: topSongs.length,
                                        itemBuilder: (context, index) {
                                          final song = topSongs[index];
                                          return GestureDetector(
                                            onTap: () {
                                              ref.read(audioServiceProvider).loadQueue(
                                                topSongs,
                                                startIndex: index,
                                                context: PlaybackContext.search,
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
                                ),
                              );
                            },
                            loading: () => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.neonPink,
                                ),
                              ),
                            ),
                            error: (err, stack) => const SizedBox.shrink(),
                          );
                        },
                      ),

                      // Bottom Icons
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Queue
                            IconButton(
                              icon: Icon(Icons.queue_music_rounded,
                                  color: AppColors.textSecondary, size: 28),
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
      ],
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
    final customTimerController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.deepSpaceBlackLight,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Sleep Timer',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  if (audioHandler.isSleepTimerActive)
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: AppColors.neonPink.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.neonPink),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Sleep timer is active',
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Timer will stop playback automatically',
                                style: TextStyle(
                                  color: AppColors.neonPink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            audioHandler.cancelSleepTimer();
                            Navigator.pop(context);
                            setState(() {});
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          ),
                          child: const Text('Cancel Sleep Timer', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        Text(
                          'Set sleep timer',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
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
                                setState(() {});
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.neonPink,
                                foregroundColor: AppColors.textPrimary,
                              ),
                              child: Text('${minutes}m'),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        Divider(color: AppColors.divider.withOpacity(0.15), indent: 40, endIndent: 40),
                        const SizedBox(height: 16),
                        Text(
                          'Or set custom duration',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: customTimerController,
                                  style: const TextStyle(color: Colors.white),
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    hintText: 'Minutes',
                                    hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.4)),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.textSecondary.withOpacity(0.5)),
                                    ),
                                    focusedBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.neonPink),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton(
                                onPressed: () {
                                  final minutes = int.tryParse(customTimerController.text.trim());
                                  if (minutes != null && minutes > 0) {
                                    audioHandler.setSleepTimer(Duration(minutes: minutes));
                                    Navigator.pop(context);
                                    setState(() {});
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.neonPink,
                                  foregroundColor: AppColors.textPrimary,
                                ),
                                child: const Text('Set'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),
                ],
              ),
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
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
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
      backgroundColor: AppColors.deepSpaceBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Player Options',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.equalizer, color: AppColors.textPrimary),
              title: Text(
                'Audio Equalizer & Boost',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                'Advanced settings',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () {
                Navigator.pop(context);
                final audioService = ref.read(audioServiceProvider);
                _showAudioSettingsDialog(context, audioService);
              },
            ),
            ListTile(
              leading: Icon(Icons.palette_rounded, color: AppColors.textPrimary),
              title: Text(
                'App Theme & Colors',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                'Customize colors and dark/light mode',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () {
                Navigator.pop(context);
                ThemeSelectionDialog.show(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.share, color: AppColors.textPrimary),
              title: Text(
                'Share Song',
                style: TextStyle(color: AppColors.textPrimary),
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

  void _showAudioSettingsDialog(BuildContext context, AudioServiceHandler audioService) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.deepSpaceBlackLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.deepSpaceBlackLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: AppColors.neonPink.withValues(alpha: 0.15),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: StatefulBuilder(
              builder: (context, setStateLocal) {
                return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Text(
                    'Audio Settings',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Volume / Audio Boost Control
                  StreamBuilder<double>(
                    stream: audioService.volumeStream,
                    initialData: audioService.volumeMultiplier,
                    builder: (context, snapshot) {
                      final volume = snapshot.data ?? 1.0;
                      return Row(
                        children: [
                          Icon(
                            volume == 0 ? Icons.volume_mute : Icons.volume_up,
                            color: AppColors.textPrimary,
                            size: 24,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                                activeTrackColor: AppColors.neonPink,
                                inactiveTrackColor: AppColors.divider.withOpacity(0.3),
                                thumbColor: AppColors.neonPink,
                                overlayColor: AppColors.neonPink.withOpacity(0.2),
                              ),
                              child: Slider(
                                value: volume,
                                min: 0.0,
                                max: audioService.maxVolumeLimit,
                                onChanged: (val) {
                                  audioService.setVolume(val);
                                  setStateLocal(() {});
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(volume * 100).toInt()}%',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  // Advanced Audio Settings
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Bass Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('BASS GAIN', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          Text('${(audioService.bassGain * 100).toInt()}%', style: TextStyle(color: AppColors.neonPink, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: audioService.bassGain > 0 ? AppColors.neonPink : AppColors.divider,
                          inactiveTrackColor: AppColors.divider,
                          thumbColor: audioService.bassGain > 0 ? AppColors.neonPink : AppColors.textSecondary,
                        ),
                        child: Slider(
                          value: audioService.bassGain,
                          onChanged: (val) {
                            audioService.setBassGain(val);
                            setStateLocal(() {});
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Treble Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('TREBLE GAIN', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          Text('${(audioService.trebleGain * 100).toInt()}%', style: TextStyle(color: AppColors.neonPink, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: audioService.trebleGain > 0 ? AppColors.neonPink : AppColors.divider,
                          inactiveTrackColor: AppColors.divider,
                          thumbColor: audioService.trebleGain > 0 ? AppColors.neonPink : AppColors.textSecondary,
                        ),
                        child: Slider(
                          value: audioService.trebleGain,
                          onChanged: (val) {
                            audioService.setTrebleGain(val);
                            setStateLocal(() {});
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Max Volume Selector
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('MAX VOLUME OVERRIDE', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.deepSpaceBlack,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.neonPink.withValues(alpha: 0.5), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.neonPink.withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                )
                              ]
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<double>(
                                value: audioService.maxVolumeLimit,
                                dropdownColor: AppColors.deepSpaceBlackLight,
                                icon: Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Icon(Icons.flash_on, color: AppColors.neonPink, size: 16),
                                ),
                                style: TextStyle(
                                  color: AppColors.textPrimary, 
                                  fontSize: 12, 
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                                items: const [
                                  DropdownMenuItem(value: 2.0, child: Text('MAX 200%')),
                                  DropdownMenuItem(value: 3.0, child: Text('MAX 300%')),
                                  DropdownMenuItem(value: 4.0, child: Text('MAX 400%')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    audioService.setMaxVolumeLimit(val);
                                    setStateLocal(() {});
                                    setState(() {});
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              );
            }
          ),
          ),
        );
      }
    );
  }
}

class GlowingRoundSliderThumbShape extends RoundSliderThumbShape {
  final Color glowColor;
  final double glowRadius;

  const GlowingRoundSliderThumbShape({
    super.enabledThumbRadius = 10.0,
    required this.glowColor,
    this.glowRadius = 8.0,
  });

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    
    // Draw the glow shadow under the thumb
    final Paint shadowPaint = Paint()
      ..color = glowColor.withOpacity(0.4)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius);
    canvas.drawCircle(center, enabledThumbRadius + 3, shadowPaint);

    super.paint(
      context,
      center,
      activationAnimation: activationAnimation,
      enableAnimation: enableAnimation,
      isDiscrete: isDiscrete,
      labelPainter: labelPainter,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      textDirection: textDirection,
      value: value,
      textScaleFactor: textScaleFactor,
      sizeWithOverflow: sizeWithOverflow,
    );
  }
}