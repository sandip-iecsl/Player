import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_provider.dart';
import '../providers/visualizer_provider.dart';
import '../providers/torch_provider.dart';
import '../widgets/enhanced_visualizer.dart';
import '../widgets/style_preview_painter.dart';
import '../../domain/entities/song.dart';

class VisualizerScreen extends ConsumerStatefulWidget {
  final Song song;
  const VisualizerScreen({super.key, required this.song});

  @override
  ConsumerState<VisualizerScreen> createState() => _VisualizerScreenState();
}

class _VisualizerScreenState extends ConsumerState<VisualizerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Target heights that we lerp FROM
  final List<double> _currentHeights = List.generate(120, (_) => 0.15);
  // Target heights we lerp TO (updated on beat)
  final List<double> _targetHeights = List.generate(120, (_) => 0.15);

  final Random _random = Random();
  bool _showHUD = true;
  Timer? _hideHUDTimer;
  Timer? _beatTimer;
  Color _currentColor = const Color(0xFF1DB954);
  double _hue = 120.0;
  double _pulse = 0.8;
  bool _isNavigatingBack = false;

  final double _deviceVolume = 1.0; // Fixed volume for visualizer scaling

  @override
  void initState() {
    super.initState();
    // Beat sync is only activated when user explicitly taps the Beat button
    // Do NOT auto-activate on screen open
    
    // Force landscape + hide status bar
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // ── Smooth animation: 30fps is plenty for a bar visualizer ──
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // ~60fps for ultra-smoothness
    )
      ..addListener(_onAnimationTick)
      ..repeat();

    // ── Enhanced harmonic simulation with better beat responsiveness ──
    _beatTimer = Timer.periodic(const Duration(milliseconds: 40), (_) { // Faster updates for smoother animation
      if (!mounted) return;
      final settings = ref.read(visualizerSettingsProvider);
      
      if (settings.autoColor) {
        _hue = (_hue + 2.0) % 360; // Faster color cycling for more dynamic effect
        _currentColor = HSVColor.fromAHSV(1.0, _hue, 1.0, 1.0).toColor();
      } else {
        _currentColor = settings.barColor;
      }

      final isPlaying = ref.read(isPlayingProvider).value ?? false;
      final time = DateTime.now().millisecondsSinceEpoch / 1000.0;

      if (isPlaying) {
        // High-energy multi-layered beat simulation
        final bassBeat = sin(time * 14.0).abs() * 0.55; 
        final midBeat = sin(time * 28.0).abs() * 0.35; 
        final highBeat = sin(time * 56.0).abs() * 0.2; 
        final randomVariation = _random.nextDouble() * 0.25;
        
        _pulse = (0.2 + bassBeat + midBeat + highBeat + randomVariation).clamp(0.0, 1.0);
        
        // Send beat intensity to torch for beat-sync flashing
        if (settings.beatSyncFlash) {
          ref.read(torchProvider.notifier).onBeat(_pulse);
        }
      } else {
        _pulse = max(0.01, _pulse * 0.9); // Slower decay for smoother fade-out
      }

      // Enhanced frequency distribution with bass emphasis and harmonic overtones
      for (int i = 0; i < _targetHeights.length; i++) {
        final freqRatio = i / _targetHeights.length;
        
        // Bass emphasis (first 30% of spectrum gets boost)
        final bassWeight = freqRatio < 0.3 ? 1.5 : 0.8;
        
        // Multiple oscillators for richer harmonics
        final osc1 = sin(time * 4.0 + i * 0.15) * 0.2;
        final osc2 = sin(time * 1.2 - i * 0.08) * 0.15;
        final osc3 = sin(time * 0.6 + i * 0.05) * 0.1; // Slow wave for movement
        
        // Harmonic overtones based on frequency position
        final harmonic = sin(time * 12.0 + i * 0.3) * 0.1 * (1.0 - freqRatio);
        
        final base = (0.25 + osc1 + osc2 + osc3 + harmonic + _random.nextDouble() * 0.08).clamp(0.0, 1.0);
        
        _targetHeights[i] = (base * bassWeight * _pulse * (_deviceVolume * 1.8 + 0.3)).clamp(0.02, 1.0);
      }
    });

    _startHideHUDTimer();
  }

  void _onAnimationTick() {
    if (!mounted || _isNavigatingBack) return;
    setState(() {
      for (int i = 0; i < _currentHeights.length; i++) {
        // Enhanced damping with beat-responsive speed
        final dampingFactor = 0.25 + (_pulse * 0.15); // Faster response on beats
        _currentHeights[i] +=
            (_targetHeights[i] - _currentHeights[i]) * dampingFactor;
      }
    });
  }

  void _startHideHUDTimer() {
    _hideHUDTimer?.cancel();
    _hideHUDTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _showHUD = false);
    });
  }

  void _toggleHUD() {
    setState(() => _showHUD = !_showHUD);
    if (_showHUD) _startHideHUDTimer();
  }

  Future<void> _goBack() async {
    if (_isNavigatingBack) return; // prevent double-tap crash
    _isNavigatingBack = true;

    _beatTimer?.cancel();
    _hideHUDTimer?.cancel();
    _controller.stop();

    if (mounted) Navigator.of(context).pop();
  }

  // All styles are handled by EnhancedVisualizerPainter
  bool _isEnhancedStyle(VisualizerStyle style) => true;
  VisualizerStyle _mapToEnhancedStyle(VisualizerStyle style) => style;

  @override
  void dispose() {
    _beatTimer?.cancel();
    _hideHUDTimer?.cancel();
    _controller.dispose();
    // ── Deactivate beat-sync torch mode ──────────────────────────
    // Deactivate beat-sync immediately while still mounted to avoid using
    // `ref` after the widget is disposed (microtask caused a Bad state).
    try {
      ref.read(torchProvider.notifier).deactivateBeatSync();
    } catch (_) {}
    // Safety net: always restore orientation and UI
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final settings = ref.watch(visualizerSettingsProvider);
    final torchState = ref.watch(torchProvider);

    ref.listen<AsyncValue<bool>>(isPlayingProvider, (_, next) {
      final playing = next.value ?? false;
      if (playing && !_controller.isAnimating) {
        _controller.repeat();
      } else if (!playing && _controller.isAnimating) {
        // Don't stop — keep lerping to zero targets for smooth dim-out
      }
    });

    final screenH = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark,
          child: GestureDetector(
            onTap: _toggleHUD,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Radial background glow ──────────────────────────────
                Center(
                  child: Container(
                    width: 1000, // Increased size
                    height: 1000,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _currentColor.withOpacity(0.25), // Increased opacity
                          _currentColor.withOpacity(0.05),
                          Colors.transparent,
                        ],
                        stops: const [
                          0.0,
                          0.4,
                          1.0
                        ], // Sharper center, broader falloff
                      ),
                    ),
                  ),
                ),

                // ── Visualizer ─────────────────────────────────────────
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: EnhancedVisualizerPainter(
                        heights: _currentHeights,
                        animationValue: _controller.value,
                        primaryColor: _currentColor,
                        style: settings.style,
                        pulse: _pulse,
                      ),
                    ),
                  ),
                ),

                // ── HUD overlay ─────────────────────────────────────────
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 350),
                  opacity: _showHUD ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !_showHUD,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Top-left: back + track info
                        Positioned(
                          top: 14,
                          left: 12,
                          right: 130, // leave space for settings panel
                          child: Row(
                            children: [
                              _glassButton(
                                icon: Icons.arrow_back_ios_new_rounded,
                                onTap: _goBack,
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.song.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        shadows: [
                                          Shadow(
                                              color: Colors.black87,
                                              blurRadius: 10)
                                        ],
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      widget.song.artist,
                                      style: const TextStyle(
                                          color: Colors.white60, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Bottom-center: music controls (prev, play/pause, next)
                        Positioned(
                          bottom: 18,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Previous button
                                GestureDetector(
                                  onTap: () => ref.read(audioServiceProvider).skipToPrevious(),
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black.withOpacity(0.65),
                                      border: Border.all(color: _currentColor.withOpacity(0.7), width: 1.5),
                                    ),
                                    child: const Icon(
                                      Icons.skip_previous_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                ),
                                
                                const SizedBox(width: 20),
                                
                                // Play/Pause button (main)
                                GestureDetector(
                                  onTap: () {
                                    if (isPlaying) {
                                      ref.read(audioServiceProvider).pause();
                                    } else {
                                      ref.read(audioServiceProvider).play();
                                    }
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black.withOpacity(0.65),
                                      border: Border.all(
                                          color: _currentColor, width: 2.5),
                                      boxShadow: [
                                        BoxShadow(
                                            color: _currentColor.withOpacity(0.6),
                                            blurRadius: 20)
                                      ],
                                    ),
                                    child: Icon(
                                      isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 36,
                                    ),
                                  ),
                                ),
                                
                                const SizedBox(width: 20),
                                
                                // Next button
                                GestureDetector(
                                  onTap: () => ref.read(audioServiceProvider).skipToNext(),
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black.withOpacity(0.65),
                                      border: Border.all(color: _currentColor.withOpacity(0.7), width: 1.5),
                                    ),
                                    child: const Icon(
                                      Icons.skip_next_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Right panel: settings
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 10),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.65),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: Colors.white10),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black54, blurRadius: 16)
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _hudBtn(
                                    icon: Icons.color_lens_rounded,
                                    label: 'Color',
                                    onTap: () => _showColorPicker(context),
                                  ),
                                  const SizedBox(height: 18),
                                  _hudBtn(
                                    icon: settings.autoColor
                                        ? Icons.auto_awesome_rounded
                                        : Icons.auto_awesome_outlined,
                                    label: 'Auto',
                                    color: settings.autoColor
                                        ? _currentColor
                                        : Colors.white54,
                                    onTap: () => ref
                                        .read(
                                            visualizerSettingsProvider.notifier)
                                        .toggleAutoColor(),
                                  ),
                                  const SizedBox(height: 18),
                                  const SizedBox(height: 18),
                                  _hudBtn(
                                    icon: Icons.style_rounded,
                                    label: 'Style',
                                    color: Colors.white,
                                    onTap: () => _showStylePicker(context),
                                  ),
                                  const SizedBox(height: 18),
                                  _hudBtn(
                                    icon: torchState.isActive
                                        ? (torchState.isBeatSync
                                            ? Icons.flash_on_rounded
                                            : Icons.flashlight_on_rounded)
                                        : Icons.flashlight_off_rounded,
                                    label: torchState.isBeatSync ? 'Beat' : 'Torch',
                                    color: torchState.isActive
                                        ? (torchState.isBeatSync
                                            ? Colors.orange
                                            : Colors.yellow)
                                        : Colors.white54,
                                    onTap: () async {
                                      final torchNotifier = ref.read(torchProvider.notifier);
                                      final vizNotifier = ref.read(visualizerSettingsProvider.notifier);
                                      
                                      if (!torchState.isActive) {
                                        // First tap: activate beat-sync flash
                                        await torchNotifier.activateBeatSync();
                                        vizNotifier.toggleBeatSync();
                                      } else if (torchState.isBeatSync) {
                                        // Second tap: switch to steady torch
                                        await torchNotifier.deactivateBeatSync();
                                        vizNotifier.toggleBeatSync();
                                        await torchNotifier.toggleActive();
                                      } else {
                                        // Third tap: turn off
                                        await torchNotifier.toggleActive();
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 18),
                                  // Help button removed as requested
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _hudBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color color = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon,
              color: onTap == null ? Colors.grey.shade800 : color, size: 24),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  color: onTap == null ? Colors.grey.shade800 : Colors.white54,
                  fontSize: 9)),
        ],
      ),
    );
  }

  void _showStylePicker(BuildContext context) {
    final styleNames = {
      VisualizerStyle.enhancedBars:        'Enhanced Bars',
      VisualizerStyle.enhancedGlowingBars: 'Glow Bars',
      VisualizerStyle.liquidWave:          'Liquid Wave',
      VisualizerStyle.oscilloscopeWave:    'Oscilloscope',
      VisualizerStyle.neonRings:           'Neon Rings',
      VisualizerStyle.radialBeat:          'Radial Beat',
      VisualizerStyle.beatPulseWave:       'Beat Pulse',
      VisualizerStyle.tunnelRings:         'Tunnel Rings',
      VisualizerStyle.fireWave:            'Fire Wave',
      VisualizerStyle.morphBlob:           'Morph Blob',
      VisualizerStyle.auroraCurtain:       'Aurora Curtain',
      VisualizerStyle.plasmaOrb:           'Plasma Orb',
      VisualizerStyle.beatRipple:          'Beat Ripple Style',
      VisualizerStyle.kaleidoscope:        'Kaleidoscope',
      VisualizerStyle.spectrumBurst:       'Spectrum Burst',
      VisualizerStyle.waveStack:           'Wave Stack',
      VisualizerStyle.mandalaPattern:      'Mandala',
      VisualizerStyle.equalizerBands:      'Equalizer Bands',
      VisualizerStyle.beatPulse:           'Beat Pulse',
    };

    final originalStyle = ref.read(visualizerSettingsProvider).style;
    var committed = false;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      // Transparent barrier — visualizer stays fully visible behind popup
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: 0.30,
            heightFactor: 0.88,
            child: SlideTransition(
              position: Tween<Offset>(
                      begin: const Offset(1, 0), end: Offset.zero)
                  .animate(CurvedAnimation(
                      parent: anim1, curve: Curves.easeOutCubic)),
              child: _EffectSelectionPanel(
                styleNames: styleNames,
                currentColor: _currentColor,
                initialStyle: originalStyle,
                onStylePreview: (style) {
                  // Live preview — apply immediately without committing
                  ref.read(visualizerSettingsProvider.notifier).setStyle(style);
                },
                onConfirm: () {
                  committed = true;
                  Navigator.pop(ctx);
                },
                onCancel: () => Navigator.pop(ctx),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      // If user dismissed without confirming, revert to original
      if (!committed) {
        ref.read(visualizerSettingsProvider.notifier).setStyle(originalStyle);
      }
    });
  }

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = [
          const Color(0xFF1DB954), // Spotify Green
          const Color(0xFF00D4FF), // Cyan
          const Color(0xFFFF3D6B), // Red Pink
          const Color(0xFFB24BF3), // Purple
          const Color(0xFFFF8C00), // Orange
          Colors.white,
          const Color(0xFFFF007F), // Neon Pink
          const Color(0xFF6200EA), // Deep Purple
          const Color(0xFFFFC107), // Amber
          const Color(0xFF00E676), // Mint
          const Color(0xFFE91E63), // Pink
          const Color(0xFF2196F3), // Blue
        ];

        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 350),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, 200 * (1 - value)),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF1A1A1A).withOpacity(0.95),
                    const Color(0xFF0A0A0A).withOpacity(0.98),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                border: Border.all(color: _currentColor.withOpacity(0.3), width: 1),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle bar
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      Text(
                        'Choose Color',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: _currentColor.withOpacity(0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: colors.asMap().entries.map((entry) {
                          final index = entry.key;
                          final color = entry.value;
                          final isSelected = ref.read(visualizerSettingsProvider).barColor == color;
                          
                          return TweenAnimationBuilder<double>(
                            duration: Duration(milliseconds: 200 + (index * 50)),
                            tween: Tween(begin: 0.0, end: 1.0),
                            builder: (context, animValue, child) => Transform.scale(
                              scale: 0.5 + (0.5 * animValue),
                              child: Opacity(
                                opacity: animValue,
                                child: GestureDetector(
                                  onTap: () {
                                    ref.read(visualizerSettingsProvider.notifier).setBarColor(color);
                                    Navigator.pop(ctx);
                                  },
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected ? Colors.white : Colors.white30,
                                        width: isSelected ? 3 : 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withOpacity(0.6),
                                          blurRadius: isSelected ? 15 : 8,
                                          spreadRadius: isSelected ? 2 : 0,
                                        ),
                                      ],
                                    ),
                                    child: isSelected ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 24,
                                    ) : null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Effect Selection Panel (Right-Side Popup, transparent background) ──────
class _EffectSelectionPanel extends ConsumerStatefulWidget {
  final Map<VisualizerStyle, String> styleNames;
  final Color currentColor;
  final VisualizerStyle initialStyle;
  final Function(VisualizerStyle) onStylePreview;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _EffectSelectionPanel({
    required this.styleNames,
    required this.currentColor,
    required this.initialStyle,
    required this.onStylePreview,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  ConsumerState<_EffectSelectionPanel> createState() =>
      _EffectSelectionPanelState();
}

class _EffectSelectionPanelState
    extends ConsumerState<_EffectSelectionPanel> {
  late VisualizerStyle _previewStyle;

  @override
  void initState() {
    super.initState();
    _previewStyle = widget.initialStyle;
  }

  void _handleTap(VisualizerStyle style) {
    setState(() => _previewStyle = style);
    widget.onStylePreview(style); // live preview
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.currentColor;

    return GestureDetector(
      onTap: () {}, // absorb taps so barrier doesn't close
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          // Semi-transparent dark panel — visualizer visible behind it
          color: const Color(0xFF0D0D0D).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: color.withValues(alpha: 0.25), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: color, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Effects',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onCancel,
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white54, size: 18),
                  ),
                ],
              ),
            ),

            // ── Scrollable list ──────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: VisualizerStyle.values.length,
                itemBuilder: (context, index) {
                  final style = VisualizerStyle.values[index];
                  final isSelected = _previewStyle == style;
                  final name =
                      widget.styleNames[style] ?? style.name;

                  return GestureDetector(
                    onTap: () => _handleTap(style),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? color.withValues(alpha: 0.55)
                              : Colors.white.withValues(alpha: 0.07),
                          width: isSelected ? 1.2 : 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Mini preview
                          Container(
                            width: 38,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: CustomPaint(
                              painter: StylePreviewPainter(
                                style: style,
                                color: isSelected
                                    ? color
                                    : Colors.white54,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white60,
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle_rounded,
                                color: color, size: 14),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Footer buttons ───────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: color.withValues(alpha: 0.15), width: 1)),
              ),
              child: Column(
                children: [
                  const Text(
                    'Tap to preview live',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: widget.onCancel,
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: Colors.white24, width: 0.8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Cancel',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: widget.onConfirm,
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Apply',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

