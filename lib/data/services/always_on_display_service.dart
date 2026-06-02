import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'audio_service.dart' show audioHandler;
import 'package:record/record.dart';

/// Service to handle always-on display functionality and enhanced notification controls
class AlwaysOnDisplayService {
  static const MethodChannel _channel = MethodChannel('aura_player/always_on_display');
  
  static bool _isAlwaysOnDisplayActive = false;
  static Timer? _keepAliveTimer;
  static StreamController<bool>? _statusController;

  /// Stream to monitor always-on display status
  static Stream<bool> get statusStream {
    _statusController ??= StreamController<bool>.broadcast();
    return _statusController!.stream;
  }

  /// Check if always-on display is currently active
  static bool get isActive => _isAlwaysOnDisplayActive;

  static bool _isSupported = false;
  static bool _pluginMissing = false;

  /// Initialize always-on display service
  static Future<void> initialize() async {
    try {
      // Set up method channel handler for native callbacks
      _channel.setMethodCallHandler(_handleMethodCall);
      
      // Check initial always-on display status
      final isSupported = await _channel.invokeMethod<bool>('isAlwaysOnDisplaySupported') ?? false;
      
      if (isSupported) {
        _isSupported = true;
        debugPrint('✅ Always-on display is supported');
        await _enableAlwaysOnDisplayOptimizations();
      } else {
        debugPrint('⚠️ Always-on display not supported on this device');
      }
    } on MissingPluginException {
      _pluginMissing = true;
      debugPrint('ℹ️ Always-on display plugin not implemented on this platform');
    } catch (e) {
      debugPrint('❌ Failed to initialize always-on display service: $e');
    }
  }

  /// Enable always-on display optimizations for music controls
  static Future<void> enableMusicControlsOnAOD() async {
    if (_pluginMissing) return;
    try {
      // Store current playback state BEFORE any native calls
      final wasPlaying = audioHandler.playbackState.value.playing;
      final currentPosition = audioHandler.playbackState.value.updatePosition;
      
      _isAlwaysOnDisplayActive = true;
      _statusController?.add(true);
      
      // Configure notification to be visible on always-on display with enhanced audio focus handling
      await _channel.invokeMethod('enableMusicControlsOnAOD', {
        'priority': 'high',
        'category': 'transport',
        'visibility': 'public',
        'showWhenLocked': true,
        'allowOnLockScreen': true,
        'maintainAudioFocus': true, // Prevent audio focus loss
        'keepScreenOn': false, // Don't interfere with AOD
        'preventPause': true, // Explicitly prevent pausing during AOD transition
      });

      // Start keep-alive timer to maintain AOD presence
      _startKeepAliveTimer();
      
      // Optimize screen brightness and refresh rate for AOD
      await _optimizeForAOD();
      
      debugPrint('✅ Music controls enabled on always-on display');

      // Ensure playback continues if it was interrupted during AOD setup
      await Future.delayed(const Duration(milliseconds: 100)); // Small delay for native setup
      
      if (wasPlaying && !audioHandler.playbackState.value.playing) {
        debugPrint('🔄 Restoring playback after AOD setup');
        await audioHandler.seek(currentPosition);
        await audioHandler.play();
      }
    } catch (e) {
      debugPrint('❌ Failed to enable music controls on AOD: $e');
    }
  }

  /// Disable always-on display music controls
  static Future<void> disableMusicControlsOnAOD() async {
    try {
      // Preserve playback state and position before disabling AOD
      final wasPlaying = audioHandler.playbackState.value.playing;
      final currentPosition = audioHandler.playbackState.value.updatePosition;

      _isAlwaysOnDisplayActive = false;
      _statusController?.add(false);
      
      await _channel.invokeMethod('disableMusicControlsOnAOD', {
        'maintainAudioFocus': true, // Keep audio focus during transition
        'preventPause': true, // Don't pause during AOD disable
      });
      
      _stopKeepAliveTimer();
      
      debugPrint('✅ Music controls disabled on always-on display');

      // Ensure playback continues after AOD disable with small delay for native cleanup
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (wasPlaying && !audioHandler.playbackState.value.playing) {
        debugPrint('🔄 Restoring playback after AOD disable');
        await audioHandler.seek(currentPosition);
        await audioHandler.play();
      }
    } catch (e) {
      debugPrint('❌ Failed to disable music controls on AOD: $e');
    }
  }

  /// Update music information on always-on display
  static Future<void> updateMusicInfo({
    required String title,
    required String artist,
    String? album,
    String? artworkUrl,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) async {
    if (!_isAlwaysOnDisplayActive || _pluginMissing) return;

    try {
      await _channel.invokeMethod('updateMusicInfo', {
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'isPlaying': isPlaying,
        'position': position.inMilliseconds,
        'duration': duration.inMilliseconds,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('❌ Failed to update music info on AOD: $e');
    }
  }

  /// Set custom AOD layout for music controls
  static Future<void> setCustomAODLayout({
    required String layoutType,
    Map<String, dynamic>? customParams,
  }) async {
    if (_pluginMissing) return;
    try {
      await _channel.invokeMethod('setCustomAODLayout', {
        'layoutType': layoutType, // 'compact', 'full', 'visualizer'
        'customParams': customParams ?? {},
      });
    } catch (e) {
      debugPrint('❌ Failed to set custom AOD layout: $e');
    }
  }

  /// Enable beat-responsive effects on AOD
  static Future<void> enableBeatResponseOnAOD(double intensity) async {
    if (!_isAlwaysOnDisplayActive || _pluginMissing) return;

    try {
      await _channel.invokeMethod('enableBeatResponse', {
        'intensity': intensity.clamp(0.0, 1.0),
        'enablePulse': true,
        'enableColorShift': true,
      });
    } catch (e) {
      debugPrint('❌ Failed to enable beat response on AOD: $e');
    }
  }

  /// Private methods

  static Future<void> _enableAlwaysOnDisplayOptimizations() async {
    try {
      await _channel.invokeMethod('enableAODOptimizations', {
        'reduceBrightness': true,
        'optimizeRefreshRate': true,
        'enableDozeMode': true,
      });
    } catch (e) {
      debugPrint('❌ Failed to enable AOD optimizations: $e');
    }
  }

  static Future<void> _optimizeForAOD() async {
    try {
      // Reduce screen brightness for AOD
      await _channel.invokeMethod('setAODBrightness', {'brightness': 0.1});
      
      // Set optimal refresh rate for AOD (usually 1Hz or 10Hz)
      await _channel.invokeMethod('setAODRefreshRate', {'refreshRate': 10});
      
    } catch (e) {
      debugPrint('❌ Failed to optimize for AOD: $e');
    }
  }

  static void _startKeepAliveTimer() {
    _stopKeepAliveTimer();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendKeepAlive();
    });
  }

  static void _stopKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  static Future<void> _sendKeepAlive() async {
    try {
      await _channel.invokeMethod('keepAlive');
    } catch (e) {
      debugPrint('❌ Keep alive failed: $e');
    }
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onAODStatusChanged':
        final isActive = call.arguments['isActive'] as bool? ?? false;
        _isAlwaysOnDisplayActive = isActive;
        _statusController?.add(isActive);
        break;
        
      case 'onMusicControlPressed':
        final action = call.arguments['action'] as String?;
        await _handleMusicControlAction(action);
        break;
        
      default:
        debugPrint('Unknown method call: ${call.method}');
    }
  }

  static Future<void> _handleMusicControlAction(String? action) async {
    // This would be handled by the audio service
    debugPrint('Music control action from AOD: $action');
  }

  /// Cleanup resources
  static void dispose() {
    _stopKeepAliveTimer();
    _statusController?.close();
    _statusController = null;
  }
}

/// Widget to display enhanced music controls optimized for always-on display
class AODMusicControlsWidget extends StatefulWidget {
  final String title;
  final String artist;
  final String? albumArt;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;

  const AODMusicControlsWidget({
    super.key,
    required this.title,
    required this.artist,
    this.albumArt,
    required this.isPlaying,
    required this.position,
    required this.duration,
    this.onPlayPause,
    this.onNext,
    this.onPrevious,
  });

  @override
  State<AODMusicControlsWidget> createState() => _AODMusicControlsWidgetState();
}

class _AODMusicControlsWidgetState extends State<AODMusicControlsWidget>
    with SingleTickerProviderStateMixin {
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final AudioRecorder _micRecorder = AudioRecorder();
  Timer? _micTimer;
  double _micLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    if (widget.isPlaying) {
      _pulseController.repeat(reverse: true);
    }
    _initializeMicMonitor();
  }

  void _initializeMicMonitor() async {
    try {
      if (!await _micRecorder.hasPermission()) return;

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
        setState(() {
          _micLevel = _mapAmplitude(amplitude.current);
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

  @override
  void didUpdateWidget(AODMusicControlsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _stopMicMonitor();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.duration.inMilliseconds > 0
        ? widget.position.inMilliseconds / widget.duration.inMilliseconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.14),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withOpacity(0.95),
            Colors.black.withOpacity(0.80),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.15,
              child: CustomPaint(
                painter: AODWavePainter(
                  level: _micLevel,
                  color: widget.isPlaying ? Colors.cyanAccent : Colors.deepPurpleAccent,
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Song info
              Row(
                children: [
                  // Album art
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: Colors.grey.withOpacity(0.3),
                    ),
                    child: widget.albumArt != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              widget.albumArt!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.music_note,
                                color: Colors.white54,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.music_note,
                            color: Colors.white54,
                          ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Text info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.artist,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              _buildMicBars(),
              
              const SizedBox(height: 14),
              
              // Progress bar
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation<Color>(
                  widget.isPlaying ? Colors.cyanAccent : Colors.white,
                ),
                minHeight: 3,
              ),
              
              const SizedBox(height: 12),
              
              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAODButton(
                    Icons.skip_previous,
                    widget.onPrevious,
                  ),
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: _buildAODButton(
                          widget.isPlaying ? Icons.pause : Icons.play_arrow,
                          widget.onPlayPause,
                          isMain: true,
                        ),
                      );
                    },
                  ),
                  _buildAODButton(
                    Icons.skip_next,
                    widget.onNext,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMicBars() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (index) {
        final base = 8.0 + index * 3;
        final height = base + (_micLevel * 24);
        return Container(
          width: 6,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.55 + _micLevel * 0.4),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildAODButton(IconData icon, VoidCallback? onPressed, {bool isMain = false}) {
    return Container(
      width: isMain ? 48 : 40,
      height: isMain ? 48 : 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isMain 
            ? Colors.white.withOpacity(0.95)
            : Colors.white.withOpacity(0.12),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.12),
            blurRadius: isMain ? 10 : 4,
            spreadRadius: isMain ? 1 : 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onPressed,
          child: Icon(
            icon,
            color: isMain ? Colors.black : Colors.white,
            size: isMain ? 24 : 20,
          ),
        ),
      ),
    );
  }
}

class AODWavePainter extends CustomPainter {
  final double level;
  final Color color;

  AODWavePainter({required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..shader = ui.Gradient.linear(
        Offset(0, size.height * 0.5),
        Offset(size.width, size.height * 0.5),
        [color.withOpacity(0.35), color.withOpacity(0.05)],
      );

    final path = Path();
    final amplitude = size.height * 0.18 * (0.4 + level * 0.6);
    final mid = size.height * 0.5;
    final step = size.width / 6;

    path.moveTo(0, mid);
    for (var i = 0; i <= 6; i++) {
      final x = step * i;
      final sinFactor = sin((i / 6) * pi * 2 + level * pi * 1.8);
      final y = mid + amplitude * sinFactor;
      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(AODWavePainter oldDelegate) {
    return oldDelegate.level != level || oldDelegate.color != color;
  }
}