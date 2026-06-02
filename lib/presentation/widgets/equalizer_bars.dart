import 'dart:math';
import 'package:flutter/material.dart';

/// Animated equalizer bars — slow, organic sine-wave movement.
///
/// The bars never snap to max height; they drift up and down gently
/// using offset sine waves with different frequencies and phases.
///
/// Usage:
///   EqualizerBars(color: Colors.green, barCount: 3, maxHeight: 20)
class EqualizerBars extends StatefulWidget {
  final Color color;
  final int barCount;
  final double maxHeight;
  final double minHeight;
  final double barWidth;
  final double spacing;

  const EqualizerBars({
    super.key,
    this.color = const Color(0xFF1DB954),
    this.barCount = 3,
    this.maxHeight = 18,
    this.minHeight = 4,
    this.barWidth = 3,
    this.spacing = 2,
  });

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  // Unique frequency and phase offset per bar so they never move in unison
  static const _freqs  = [1.1, 1.6, 1.35, 1.8, 1.45];
  static const _phases = [0.0, 1.05, 2.1, 0.55, 1.7];

  @override
  void initState() {
    super.initState();
    // 3-second cycle → slow, calm animation
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value * 2 * pi;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (i) {
            final freq  = _freqs[i % _freqs.length];
            final phase = _phases[i % _phases.length];
            // sin ranges −1..+1 → remap to 0..1
            final frac  = (sin(t * freq + phase) + 1) / 2;
            final h = widget.minHeight + frac * (widget.maxHeight - widget.minHeight);
            return Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : widget.spacing),
              child: Container(
                width: widget.barWidth,
                height: h,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(widget.barWidth / 2),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
