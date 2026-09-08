import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../domain/entities/song.dart';
import '../providers/audio_provider.dart';
import 'playlist_dialogs.dart';
import 'default_album_art.dart';
import '../../core/constants/app_colors.dart';

/// Floating mini player — completely independent pill widget.
/// Floats above the bottom nav bar, no connection to SlidingUpPanel.
class FloatingMiniPlayer extends ConsumerStatefulWidget {
  final Song song;
  final VoidCallback onTap; // opens full player

  const FloatingMiniPlayer({
    super.key,
    required this.song,
    required this.onTap,
  });

  @override
  ConsumerState<FloatingMiniPlayer> createState() => _FloatingMiniPlayerState();
}

class _FloatingMiniPlayerState extends ConsumerState<FloatingMiniPlayer>
    with SingleTickerProviderStateMixin {
  Color _accent = AppColors.neonPink;
  late AnimationController _entryCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutBack));
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);

    _entryCtrl.forward();
    _extractColor();
  }

  @override
  void didUpdateWidget(FloatingMiniPlayer old) {
    super.didUpdateWidget(old);
    if (old.song.albumArt != widget.song.albumArt) _extractColor();
  }

  Future<void> _extractColor() async {
    final url = widget.song.albumArt;
    if (url == null || url.isEmpty) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(NetworkImage(url));
      if (mounted) {
        setState(() {
          _accent = palette.vibrantColor?.color ??
              palette.dominantColor?.color ??
              AppColors.neonPink;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final position  = ref.watch(currentPositionProvider).value ?? Duration.zero;
    final duration  = ref.watch(currentDurationProvider).value ??
        widget.song.duration ?? const Duration(seconds: 1);
    final progress  = (position.inMilliseconds /
            duration.inMilliseconds.clamp(1, 999999999))
        .clamp(0.0, 1.0);
    final audio = ref.read(audioServiceProvider);

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 0),
          child: GestureDetector(
            onTap: widget.onTap,
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity! > 100) {
                audio.skipToPrevious();
              } else if (details.primaryVelocity! < -100) {
                audio.skipToNext();
              }
            },
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.35),
                    blurRadius: 24,
                    spreadRadius: 0,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: AppColors.deepSpaceBlack.withOpacity(0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  children: [
                    // ── Frosted glass background ──────────────────────────
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.deepSpaceBlack.withOpacity(0.75),
                                AppColors.deepSpaceBlack.withOpacity(0.65),
                              ],
                            ),
                            border: Border.all(
                              color: _accent.withOpacity(0.3),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                      ),
                    ),

                  // ── Progress bar at bottom ────────────────────────────
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(22),
                        bottomRight: Radius.circular(22),
                      ),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2.5,
                        backgroundColor: AppColors.textPrimary.withOpacity(0.08),
                        valueColor: AlwaysStoppedAnimation<Color>(_accent),
                      ),
                    ),
                  ),

                  // ── Content row ───────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 14, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Album art
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AlbumArtImage(
                            imageUrl: widget.song.albumArt,
                            width: 50,
                            height: 50,
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Title + artist
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.song.title,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.song.artist,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        // ── Controls ──────────────────────────────────
                        // Skip next
                        _iconBtn(
                          Icons.skip_next_rounded,
                          () => audio.skipToNext(),
                          size: 22,
                        ),

                        // Add to playlist
                        _iconBtn(
                          Icons.add_rounded,
                          () => PlaylistDialogs.showAddToPlaylist(
                              context, ref, widget.song),
                          size: 22,
                        ),

                        const SizedBox(width: 4),

                        // Play / Pause
                        GestureDetector(
                          onTap: () =>
                              isPlaying ? audio.pause() : audio.play(),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _accent,
                              boxShadow: [
                                BoxShadow(
                                  color: _accent.withOpacity(0.55),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: AppColors.deepSpaceBlack,
                              size: 24,
                            ),
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
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {double size = 22}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Icon(icon, color: AppColors.textPrimary, size: size),
        ),
      );
}
