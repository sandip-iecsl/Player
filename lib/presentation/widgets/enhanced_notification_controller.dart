import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../domain/entities/song.dart';
import '../providers/audio_provider.dart';
import 'default_album_art.dart';
import 'playlist_dialogs.dart';

/// Enhanced notification-style music controller with animations and always-on display support
class EnhancedNotificationController extends ConsumerStatefulWidget {
  final Song? currentSong;
  final bool isCompact;
  final VoidCallback? onTap;

  const EnhancedNotificationController({
    super.key,
    this.currentSong,
    this.isCompact = false,
    this.onTap,
  });

  @override
  ConsumerState<EnhancedNotificationController> createState() => _EnhancedNotificationControllerState();
}

class _EnhancedNotificationControllerState extends ConsumerState<EnhancedNotificationController>
    with TickerProviderStateMixin {
  
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnimation;
  
  Timer? _beatTimer;
  Timer? _micTimer;
  final AudioRecorder _micRecorder = AudioRecorder();
  double _beatIntensity = 0.0;
  double _micLevel = 0.0;
  Color _dominantColor = const Color(0xFF1DB954);
  final List<double> _vizHeights = List.generate(20, (_) => 0.2);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startBeatSimulation();
    _initializeMicMonitor();
  }

  void _initializeMicMonitor() async {
    try {
      if (!await _micRecorder.hasPermission()) {
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/aod_mic_monitor.aac';
      await _micRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: tempPath,
      );

      _micTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
        if (!mounted) return;
        final amplitude = await _micRecorder.getAmplitude();
        final normalized = _mapAmplitude(amplitude.current);
        setState(() {
          _micLevel = normalized;
        });
      });
    } catch (_) {
      // Microphone sampling is optional; degrade gracefully.
    }
  }

  double _mapAmplitude(double rawAmplitude) {
    if (rawAmplitude <= 0) return 0.0;
    return (rawAmplitude / 120.0).clamp(0.0, 1.0);
  }

  void _stopMicMonitor() async {
    _micTimer?.cancel();
    _micTimer = null;
    try {
      if (await _micRecorder.isRecording()) {
        await _micRecorder.stop();
      }
    } catch (_) {}
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _rotationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();
  }

  void _startBeatSimulation() {
    _beatTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      
      final isPlaying = ref.read(isPlayingProvider).value ?? false;
      if (isPlaying) {
          final time = DateTime.now().millisecondsSinceEpoch / 1000.0;
        final beat = (sin(time * 3.5) * 0.5 + 0.5) * 
                    (sin(time * 7.0) * 0.3 + 0.7);
        final combinedBeat = (beat * 0.75 + _micLevel * 0.35).clamp(0.0, 1.0);
        
        setState(() {
          _beatIntensity = combinedBeat;
          for (int i = 0; i < _vizHeights.length; i++) {
            final dynamicLevel = max(Random().nextDouble() * beat, _micLevel * 0.7);
            _vizHeights[i] = (0.2 + 0.8 * dynamicLevel).clamp(0.1, 1.0);
          }
        });

        if (combinedBeat > 0.85 && !_pulseController.isAnimating) {
          _pulseController.forward().then((_) => _pulseController.reverse());
        }
      } else {
        setState(() {
          _beatIntensity = max(0.0, _beatIntensity * 0.9);
          for (int i = 0; i < _vizHeights.length; i++) {
            _vizHeights[i] *= 0.9;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    _stopMicMonitor();
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentSong == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final audioService = ref.watch(audioServiceProvider);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: widget.isCompact ? 1.0 : _pulseAnimation.value,
            child: _buildModifiedCard(context, isPlaying, audioService),
          );
        },
      ),
    );
  }

  Widget _buildModifiedCard(BuildContext context, bool isPlaying, dynamic audioService) {
    final glowColor = _dominantColor.withOpacity(0.4 + _beatIntensity * 0.3);
    
    return Container(
      margin: widget.isCompact 
          ? const EdgeInsets.fromLTRB(10, 0, 10, 8)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: widget.isCompact ? 68 : 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: widget.isCompact ? [
          BoxShadow(
            color: glowColor.withOpacity(0.25),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ] : [
          BoxShadow(
            color: glowColor.withOpacity(0.3),
            blurRadius: 20 + _beatIntensity * 15,
            spreadRadius: 1 + _beatIntensity * 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Transparent glassmorphic background — no solid color
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.12),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
            
            // Subtle animated neon border (compact only shows faint version)
            Positioned.fill(
              child: CustomPaint(
                painter: NeonBorderPainter(
                  progress: _rotationController.value,
                  color: _dominantColor,
                  intensity: widget.isCompact ? _beatIntensity * 0.4 : _beatIntensity,
                ),
              ),
            ),

            // Background Visualizer bars
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: widget.isCompact ? 20 : 40,
              child: Opacity(
                opacity: 0.2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _vizHeights.map((h) => Container(
                    width: 3,
                    height: (widget.isCompact ? 20 : 40) * h,
                    decoration: BoxDecoration(
                      color: _dominantColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )).toList(),
                ),
              ),
            ),

            // Content
            Padding(
              padding: widget.isCompact 
                  ? const EdgeInsets.fromLTRB(10, 0, 10, 0)
                  : const EdgeInsets.all(16.0),
              child: widget.isCompact 
                  ? _buildCompactLayout(isPlaying, audioService)
                  : _buildFullLayout(isPlaying, audioService),
            ),

            // Progress bar at bottom
            _buildProgressIndicator(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(BuildContext context) {
    final currentPosition = ref.watch(currentPositionProvider).value ?? Duration.zero;
    final totalDuration = ref.watch(currentDurationProvider).value ?? 
                         widget.currentSong?.duration ?? 
                         const Duration(seconds: 1);
    final progress = currentPosition.inMilliseconds / 
                    totalDuration.inMilliseconds.clamp(1, 10000000);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 2,
        color: Colors.white.withOpacity(0.1),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: _dominantColor,
              boxShadow: [
                BoxShadow(
                  color: _dominantColor,
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactLayout(bool isPlaying, dynamic audioService) {
    return SizedBox(
      height: 68,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Album art
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 46,
              height: 46,
              child: AlbumArtImage(
                imageUrl: widget.currentSong!.albumArt,
                width: 46,
                height: 46,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Title + artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.currentSong!.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.currentSong!.artist,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Next button
          GestureDetector(
            onTap: () => audioService.skipToNext(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.skip_next_rounded, color: Colors.white, size: 22),
            ),
          ),
          // Add to playlist button
          GestureDetector(
            onTap: () => PlaylistDialogs.showAddToPlaylist(context, ref, widget.currentSong!),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.add_rounded, color: Colors.white, size: 22),
            ),
          ),
          // Play/Pause button
          GestureDetector(
            onTap: () => isPlaying ? audioService.pause() : audioService.play(),
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _dominantColor,
                boxShadow: [
                  BoxShadow(
                    color: _dominantColor.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullLayout(bool isPlaying, dynamic audioService) {
    return Column(
      children: [
        Row(
          children: [
            _buildAlbumArt(70),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.currentSong!.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.currentSong!.artist,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionIcon(Icons.skip_previous_rounded, () => audioService.skipToPrevious()),
            _buildPlayButton(isPlaying, audioService, 40),
            _buildActionIcon(Icons.skip_next_rounded, () => audioService.skipToNext()),
          ],
        ),
      ],
    );
  }

  Widget _buildAlbumArt(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _dominantColor.withOpacity(0.4),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AlbumArtImage(
          imageUrl: widget.currentSong!.albumArt,
          width: size,
          height: size,
        ),
      ),
    );
  }

  Widget _buildPlayButton(bool isPlaying, dynamic audioService, double size) {
    return GestureDetector(
      onTap: () => isPlaying ? audioService.pause() : audioService.play(),
      child: Container(
        padding: EdgeInsets.all(widget.isCompact ? 8 : 12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [_dominantColor, _dominantColor.withOpacity(0.7)],
          ),
          boxShadow: [
            BoxShadow(
              color: _dominantColor.withOpacity(0.5),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
          size: size,
        ),
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 32),
      onPressed: onTap,
    );
  }

  Widget _buildCompactActionButton(IconData icon, double size, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(
          icon,
          color: Colors.white,
          size: size,
        ),
      ),
    );
  }

  Widget _buildTorchButton(double size) {
    // Torch button removed from compact mini-player per user request.
    return const SizedBox.shrink();
  }
}

class NeonBorderPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double intensity;

  NeonBorderPainter({required this.progress, required this.color, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(24));
    
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 + intensity * 2.0
      ..shader = ui.Gradient.sweep(
        size.center(Offset.zero),
        [
          color.withOpacity(0.1),
          color,
          color.withOpacity(0.1),
        ],
        [0.0, 0.5, 1.0],
        TileMode.clamp,
        progress * 2 * pi,
        progress * 2 * pi + pi,
      );

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(NeonBorderPainter oldDelegate) => true;
}
