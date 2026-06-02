import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';
import '../providers/audio_provider.dart';
import '../providers/sync_provider.dart';
import 'playlist_dialogs.dart';
import 'package:palette_generator/palette_generator.dart';
import 'default_album_art.dart';
import 'enhanced_notification_controller.dart';
import '../../data/services/always_on_display_service.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  final Song? currentSong;
  final VoidCallback onTap;

  const MiniPlayer({
    super.key,
    this.currentSong,
    required this.onTap,
  });

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> 
    with SingleTickerProviderStateMixin {
  Color? _backgroundColor;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  bool _useEnhancedController = true;

  @override
  void initState() {
    super.initState();
    _updatePalette();
    _setupAnimations();
    _initializeAOD();
  }

  void _setupAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));

    if (widget.currentSong != null) {
      _slideController.forward();
    }
  }

  void _initializeAOD() async {
    await AlwaysOnDisplayService.initialize();
    if (widget.currentSong != null) {
      await AlwaysOnDisplayService.enableMusicControlsOnAOD();
    }
  }

  @override
  void didUpdateWidget(MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Handle song changes
    if (oldWidget.currentSong?.id != widget.currentSong?.id) {
      if (widget.currentSong != null) {
        _updatePalette();
        _slideController.forward();
        _updateAODInfo();
        if (oldWidget.currentSong == null) {
          Future.microtask(() => AlwaysOnDisplayService.enableMusicControlsOnAOD());
        }
      } else {
        _slideController.reverse();
      }
    }
    
    // Update album art palette
    if (oldWidget.currentSong?.albumArt != widget.currentSong?.albumArt) {
      _updatePalette();
    }
  }

  Future<void> _updatePalette() async {
    final song = widget.currentSong;
    if (song?.albumArt == null) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(song!.albumArt!),
      );
      setState(() {
        _backgroundColor =
            palette.vibrantColor?.color ?? palette.dominantColor?.color;
      });
    } catch (_) {}
  }

  void _updateAODInfo() {
    final song = widget.currentSong;
    if (song == null) return;

    final currentPosition = ref.read(currentPositionProvider).value ?? Duration.zero;
    final totalDuration = ref.read(currentDurationProvider).value ??
                         song.duration ?? 
                         const Duration(seconds: 1);
    final isPlaying = ref.read(isPlayingProvider).value ?? false;

    AlwaysOnDisplayService.updateMusicInfo(
      title: song.title,
      artist: song.artist,
      album: song.album,
      artworkUrl: song.albumArt,
      isPlaying: isPlaying,
      position: currentPosition,
      duration: totalDuration,
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(isPlayingProvider, (_, __) {
      _updateAODInfo();
    });
    ref.listen<AsyncValue<Duration>>(currentPositionProvider, (_, __) {
      _updateAODInfo();
    });

    if (widget.currentSong == null) return const SizedBox.shrink();

    if (_useEnhancedController) {
      return SlideTransition(
        position: _slideAnimation,
        child: Container(
          color: Colors.transparent, // transparent wrapper — card handles its own bg
          child: EnhancedNotificationController(
            currentSong: widget.currentSong,
            isCompact: true,
            onTap: widget.onTap,
          ),
        ),
      );
    }

    return _buildOriginalMiniPlayer(context);
  }

  Widget _buildOriginalMiniPlayer(BuildContext context) {
    final song = widget.currentSong;
    if (song == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final audioService = ref.watch(audioServiceProvider);
    final currentPosition =
        ref.watch(currentPositionProvider).value ?? Duration.zero;
    final totalDuration = ref.watch(currentDurationProvider).value ??
        song.duration ??
        const Duration(seconds: 1);

    final progress = currentPosition.inMilliseconds /
        totalDuration.inMilliseconds.clamp(1, 10000000);
    final syncState = ref.watch(syncProvider);

    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        width: double.infinity,
        height: 64,
        decoration: BoxDecoration(
          color: (_backgroundColor ?? const Color(0xFF1E1E1E)).withValues(alpha: 0.95),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onTap,
                        child: Row(
                          children: [
                            AlbumArtImage(
                              imageUrl: song.albumArt!,
                              width: 48,
                              height: 48,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (syncState.isActive)
                      Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          syncState.isSyncing ? Icons.sync : Icons.speaker_group,
                          color: syncState.isSyncing
                              ? const Color(0xFF1DB954)
                              : Colors.white,
                          size: 20,
                        ),
                      ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              color: Colors.white, size: 28),
                          onPressed: () => PlaylistDialogs.showAddToPlaylist(
                              context, ref, song!),
                        ),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                              onPressed: () {
                                if (isPlaying) {
                                  audioService.pause();
                                } else {
                                  audioService.play();
                                }
                              },
                            ),
                            if (syncState.isSyncing)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1DB954).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Icon(
                                      Icons.sync,
                                      color: Color(0xFF1DB954),
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 48,
        height: 48,
        color: Colors.grey[800],
        child: const Icon(Icons.music_note, color: Colors.white54, size: 24),
      );
}