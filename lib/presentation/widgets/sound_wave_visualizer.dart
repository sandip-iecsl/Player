import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:math' show sin, pi;

class SoundWaveVisualizer extends StatefulWidget {
  final double height;
  final double width;
  final List<double> frequencies;
  final double beatIntensity;
  final bool isPlaying;
  final Color? barColor;
  final bool autoColor;

  const SoundWaveVisualizer({
    super.key,
    this.height = 300,
    this.width = double.infinity,
    this.frequencies = const [],
    this.beatIntensity = 0.0,
    this.isPlaying = false,
    this.barColor,
    this.autoColor = true,
  });

  @override
  State<SoundWaveVisualizer> createState() => _SoundWaveVisualizerState();
}

class _SoundWaveVisualizerState extends State<SoundWaveVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  List<double> _smoothedFrequencies = [];
  double _smoothedBeat = 0.0;
  late Color _currentBarColor;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    )..repeat();

    // Initialize smoothed frequencies
    _smoothedFrequencies = List<double>.filled(64, 0.0);
    _currentBarColor = widget.barColor ?? const Color(0xFF00FF41);
  }

  @override
  void didUpdateWidget(SoundWaveVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.barColor != oldWidget.barColor) {
      _currentBarColor = widget.barColor ?? const Color(0xFF00FF41);
    }

    // Smooth frequency updates
    if (widget.frequencies.isNotEmpty) {
      for (int i = 0; i < _smoothedFrequencies.length; i++) {
        final targetValue =
            i < widget.frequencies.length ? widget.frequencies[i] : 0.0;
        _smoothedFrequencies[i] =
            _smoothedFrequencies[i] * 0.7 + targetValue * 0.3;
      }
    }

    // Smooth beat intensity
    _smoothedBeat = _smoothedBeat * 0.8 + widget.beatIntensity * 0.2;
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Color _getBarColor(int index, int total) {
    if (!widget.autoColor) {
      return _currentBarColor;
    }

    // Auto color - gradient from blue to green to yellow
    final hue = (index / total * 120).toDouble(); // 0-120 degrees
    return HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return CustomPaint(
          painter: EqualizerPainter(
            progress: _animationController.value,
            frequencies: _smoothedFrequencies,
            beatIntensity: _smoothedBeat,
            isPlaying: widget.isPlaying,
            getBarColor: _getBarColor,
            autoColor: widget.autoColor,
          ),
          size: Size(widget.width, widget.height),
        );
      },
    );
  }
}

class EqualizerPainter extends CustomPainter {
  final double progress;
  final List<double> frequencies;
  final double beatIntensity;
  final bool isPlaying;
  final Color Function(int index, int total) getBarColor;
  final bool autoColor;

  EqualizerPainter({
    required this.progress,
    required this.frequencies,
    required this.beatIntensity,
    required this.isPlaying,
    required this.getBarColor,
    required this.autoColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final centerX = size.width / 2;

    // Draw background gradient
    final bgGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.black.withOpacity(0.5),
        Colors.black,
        Colors.black.withOpacity(0.5),
      ],
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = bgGradient.createShader(
          Rect.fromLTWH(0, 0, size.width, size.height),
        ),
    );

    if (!isPlaying) {
      return;
    }

    _drawWaveVisualizer(canvas, size, centerX, centerY);
    _drawCenterPlayButton(canvas, centerX, centerY);
  }

  void _drawWaveVisualizer(Canvas canvas, Size size, double centerX, double centerY) {
    // Extract bass (low freq) and mid-high frequencies for dynamic mapping
    final bassFreq = frequencies.take(8).fold<double>(0, (a, b) => a + b) / 8.0;
    final midFreq = frequencies.skip(8).take(24).fold<double>(0, (a, b) => a + b) / 24.0;
    final highFreq = frequencies.skip(32).fold<double>(0, (a, b) => a + b) / frequencies.length;

    // Dynamic amplitude based on bass (left/center-left gets more movement)
    final bassAmplitude = bassFreq * 50 + beatIntensity * 25;
    
    // Dynamic wavelength based on mid frequencies (tightness of ripples)
    final wavelength = 100 + (midFreq * 80);
    
    // Phase shift for smooth animation
    final phaseShift = progress * pi * 2;

    // Draw multiple overlapping wave layers for depth
    const layerCount = 4;
    for (int layer = 0; layer < layerCount; layer++) {
      final layerOffset = layer * 12.0;
      final layerAmplitudeScale = 1.0 - (layer * 0.2);
      final layerOpacity = 0.6 - (layer * 0.12);

      // Color gradient across layers: violet → cyan → coral
      final hue = (layer / layerCount) * 360;
      final layerColor = _getNeonColor(hue);

      _drawContinuousWave(
        canvas,
        size,
        centerY + layerOffset,
        bassAmplitude * layerAmplitudeScale,
        wavelength,
        phaseShift,
        layerColor,
        layerOpacity,
      );
    }
  }

  void _drawContinuousWave(
    Canvas canvas,
    Size size,
    double baselineY,
    double amplitude,
    double wavelength,
    double phaseShift,
    Color color,
    double opacity,
  ) {
    const pointCount = 200;
    final path = Path();
    final padding = size.width * 0.1;
    final waveWidth = size.width * 0.8;

    // Build smooth bezier curve for main wave
    for (int i = 0; i < pointCount; i++) {
      final progress = i / (pointCount - 1);
      final xPos = padding + (progress * waveWidth);
      
      // Sine wave calculation with phase shift
      final angle = (progress * (size.width / wavelength)) * pi * 2 + phaseShift;
      final yPos = baselineY + (sin(angle) * amplitude);

      if (i == 0) {
        path.moveTo(xPos, yPos);
      } else {
        path.lineTo(xPos, yPos);
      }
    }

    // Draw glowing neon effect (2 passes: blur + sharp)
    final glowPaint = Paint()
      ..color = color.withOpacity(opacity * 0.4)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 18);

    canvas.drawPath(path, glowPaint);

    // Draw textured wave stroke with dotted pattern effect
    final mainPaint = Paint()
      ..color = color.withOpacity(opacity * 0.9)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, mainPaint);

    // Add subtle highlight wave for extra depth
    final highlightPath = Path();
    for (int i = 0; i < pointCount; i++) {
      final progress = i / (pointCount - 1);
      final xPos = padding + (progress * waveWidth);
      final angle = (progress * (size.width / wavelength)) * pi * 2 + phaseShift;
      final yPos = baselineY + (sin(angle) * amplitude * 0.6);

      if (i == 0) {
        highlightPath.moveTo(xPos, yPos);
      } else {
        highlightPath.lineTo(xPos, yPos);
      }
    }

    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(opacity * 0.3)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(highlightPath, highlightPaint);
  }

  Color _getNeonColor(double hue) {
    // Violet #A124F7 → Cyan #24A1F7 → Coral Pink #F724A1
    if (hue < 120) {
      // Violet to Cyan
      final t = hue / 120;
      return Color.lerp(
        const Color(0xFFA124F7),
        const Color(0xFF24A1F7),
        t,
      )!;
    } else {
      // Cyan to Coral Pink
      final t = (hue - 120) / 240;
      return Color.lerp(
        const Color(0xFF24A1F7),
        const Color(0xFFF724A1),
        t,
      )!;
    }
  }

  void _drawCenterPlayButton(Canvas canvas, double centerX, double centerY) {
    // Draw circle border
    canvas.drawCircle(
      Offset(centerX, centerY),
      35,
      Paint()
        ..color = const Color(0xFF00FF41)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Draw play icon
    final pauseRect1 = Rect.fromLTWH(centerX - 10, centerY - 8, 3, 16);
    final pauseRect2 = Rect.fromLTWH(centerX + 7, centerY - 8, 3, 16);

    canvas.drawRRect(
      RRect.fromRectAndRadius(pauseRect1, const Radius.circular(1)),
      Paint()..color = const Color(0xFF00FF41),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(pauseRect2, const Radius.circular(1)),
      Paint()..color = const Color(0xFF00FF41),
    );
  }

  @override
  bool shouldRepaint(EqualizerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.frequencies != frequencies ||
        oldDelegate.beatIntensity != beatIntensity ||
        oldDelegate.isPlaying != isPlaying;
  }
}
