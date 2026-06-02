import 'dart:math';
import 'package:flutter/material.dart';
import '../providers/visualizer_provider.dart';

/// Static mini-preview for each VisualizerStyle — used in the style picker.
class StylePreviewPainter extends CustomPainter {
  final VisualizerStyle style;
  final Color color;

  const StylePreviewPainter({required this.style, required this.color});

  // Sample heights for static previews
  static const _h = [0.3, 0.65, 0.9, 0.7, 0.45, 0.8, 0.35, 0.6, 0.85, 0.5];

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final cy = size.height / 2;
    final w = size.width;

    switch (style) {
      case VisualizerStyle.enhancedBars:
        _bottomBars(canvas, size, p, w, filled: true);
      case VisualizerStyle.enhancedGlowingBars:
        _mirroredBars(canvas, size, p, cy, w);
      case VisualizerStyle.liquidWave:
        _wave(canvas, size, p, cy, w, mirrored: true);
      case VisualizerStyle.oscilloscopeWave:
        _oscilloscope(canvas, size, p, cy, w);
      case VisualizerStyle.neonRings:
        _concentric(canvas, size, p, cy, w, count: 3);
      case VisualizerStyle.radialBeat:
        _radial(canvas, size, p, cy, w);
      case VisualizerStyle.beatPulseWave:
        _concentric(canvas, size, p, cy, w, count: 2);
        _mirroredBars(canvas, size, p, cy, w, count: 5);
      case VisualizerStyle.tunnelRings:
        _tunnelRings(canvas, size, p, cy, w);
      case VisualizerStyle.fireWave:
        _fireWave(canvas, size, p, w);
      case VisualizerStyle.morphBlob:
        _blob(canvas, size, p, cy, w);
      case VisualizerStyle.auroraCurtain:
        _aurora(canvas, size, p, cy, w);
      case VisualizerStyle.plasmaOrb:
        _plasma(canvas, size, p, cy, w);
      case VisualizerStyle.beatRipple:
        _ripple(canvas, size, p, cy, w);
      case VisualizerStyle.kaleidoscope:
        _kaleidoscope(canvas, size, p, cy, w);
      case VisualizerStyle.spectrumBurst:
        _burst(canvas, size, p, cy, w);
      case VisualizerStyle.waveStack:
        _waveStack(canvas, size, p, cy, w);
      case VisualizerStyle.mandalaPattern:
        _mandala(canvas, size, p, cy, w);
      case VisualizerStyle.equalizerBands:
        _equalizerPreview(canvas, size, p, w);
      case VisualizerStyle.beatPulse:
        _beatPulse(canvas, size, p, cy, w);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  void _bottomBars(Canvas c, Size s, Paint p, double w,
      {bool filled = false, int count = 9}) {
    p.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
    final bw = w / count;
    for (int i = 0; i < count; i++) {
      final h = s.height * 0.72 * _h[i % _h.length];
      final x = i * bw + bw / 2;
      if (filled) {
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - bw * 0.35, s.height - h, bw * 0.7, h),
            const Radius.circular(3),
          ),
          p,
        );
      } else {
        c.drawLine(Offset(x, s.height), Offset(x, s.height - h), p);
      }
    }
  }

  void _mirroredBars(Canvas c, Size s, Paint p, double cy, double w,
      {int count = 8}) {
    p.style = PaintingStyle.stroke;
    final bw = w / count;
    for (int i = 0; i < count; i++) {
      final h = s.height * 0.34 * _h[i % _h.length];
      final x = i * bw + bw / 2;
      c.drawLine(Offset(x, cy - h), Offset(x, cy + h), p);
    }
  }

  void _wave(Canvas c, Size s, Paint p, double cy, double w,
      {bool mirrored = false}) {
    p.style = PaintingStyle.stroke;
    final path = Path();
    bool first = true;
    for (double x = 0; x <= w; x += 2) {
      final t = x / w;
      final y = cy - sin(t * 5 * pi) * s.height * 0.24;
      if (first) { path.moveTo(x, y); first = false; }
      else { path.lineTo(x, y); }
    }
    c.drawPath(path, p);
    if (mirrored) {
      final path2 = Path();
      first = true;
      for (double x = 0; x <= w; x += 2) {
        final t = x / w;
        final y = cy + sin(t * 5 * pi) * s.height * 0.24;
        if (first) { path2.moveTo(x, y); first = false; }
        else { path2.lineTo(x, y); }
      }
      c.drawPath(path2, p);
    }
  }

  void _oscilloscope(Canvas c, Size s, Paint p, double cy, double w) {
    p.style = PaintingStyle.stroke;
    final path = Path();
    bool first = true;
    for (double x = 0; x <= w; x += 2) {
      final t = x / w;
      final y = cy + sin(t * 8 * pi) * s.height * 0.3 * _h[(t * 9).floor() % _h.length];
      if (first) { path.moveTo(x, y); first = false; }
      else { path.lineTo(x, y); }
    }
    c.drawPath(path, p);
  }

  void _concentric(Canvas c, Size s, Paint p, double cy, double w,
      {int count = 3}) {
    p.style = PaintingStyle.stroke;
    final cx = w / 2;
    for (int i = 0; i < count; i++) {
      p.strokeWidth = 1.8 - i * 0.3;
      c.drawCircle(Offset(cx, cy), s.height * (0.14 + i * 0.1), p);
    }
    p.strokeWidth = 1.8;
  }

  void _radial(Canvas c, Size s, Paint p, double cy, double w) {
    p.style = PaintingStyle.stroke;
    final cx = w / 2;
    final r = min(w, s.height) * 0.22;
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * 2 * pi;
      final len = r * (0.5 + _h[i % _h.length] * 0.5);
      c.drawLine(
        Offset(cx + cos(angle) * r * 0.25, cy + sin(angle) * r * 0.25),
        Offset(cx + cos(angle) * len, cy + sin(angle) * len),
        p,
      );
    }
    c.drawCircle(Offset(cx, cy), r * 0.22, p);
  }

  void _tunnelRings(Canvas c, Size s, Paint p, double cy, double w) {
    p.style = PaintingStyle.stroke;
    final cx = w / 2;
    for (int i = 1; i <= 4; i++) {
      final r = min(w, s.height) * 0.11 * i;
      p.strokeWidth = 2.5 - i * 0.4;
      p.color = color.withValues(alpha: (1.0 - i * 0.18).clamp(0.1, 1.0));
      c.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 2.2, height: r * 1.4),
        p,
      );
    }
    p.color = color;
    p.strokeWidth = 1.8;
  }

  void _fireWave(Canvas c, Size s, Paint p, double w) {
    p.style = PaintingStyle.fill;
    const n = 9;
    final bw = w / n;
    for (int i = 0; i < n; i++) {
      final h = s.height * 0.72 * _h[i % _h.length];
      final x = i * bw + bw / 2;
      final grad = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.yellow.withValues(alpha: 0.9),
          Colors.orange.withValues(alpha: 0.7),
          Colors.red.withValues(alpha: 0.4),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(x - bw / 2, s.height - h, bw, h));
      p.shader = grad;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - bw * 0.38, s.height - h, bw * 0.76, h),
          const Radius.circular(3),
        ),
        p,
      );
      p.shader = null;
    }
    p.color = color;
  }

  void _blob(Canvas c, Size s, Paint p, double cy, double w) {
    final cx = w / 2;
    final baseR = min(w, s.height) * 0.28;
    final path = Path();
    const pts = 32;
    for (int i = 0; i <= pts; i++) {
      final angle = (i / pts) * 2 * pi;
      final deform = 1.0 + sin(angle * 3) * 0.22 + sin(angle * 5) * 0.12;
      final r = baseR * deform;
      final x = cx + cos(angle) * r;
      final y = cy + sin(angle) * r;
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close();
    p.style = PaintingStyle.fill;
    p.color = color.withValues(alpha: 0.3);
    c.drawPath(path, p);
    p.color = color;
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 1.8;
    c.drawPath(path, p);
  }

  void _aurora(Canvas c, Size s, Paint p, double cy, double w) {
    // Vertical curtain-like bars with gradient
    const cols = 8;
    final bw = w / cols;
    for (int i = 0; i < cols; i++) {
      final h = s.height * 0.7 * _h[i % _h.length];
      final x = i * bw;
      final grad = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.6),
          color.withValues(alpha: 0.9),
          color.withValues(alpha: 0.4),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(x, cy - h / 2, bw, h));
      p.style = PaintingStyle.fill;
      p.shader = grad;
      c.drawRect(Rect.fromLTWH(x + 1, cy - h / 2, bw - 2, h), p);
      p.shader = null;
    }
    p.color = color;
  }

  void _plasma(Canvas c, Size s, Paint p, double cy, double w) {
    p.style = PaintingStyle.stroke;
    final cx = w / 2;
    final r = min(w, s.height) * 0.28;
    // Core circle
    p.strokeWidth = 2.0;
    c.drawCircle(Offset(cx, cy), r * 0.35, p);
    // Arcs
    for (int i = 0; i < 6; i++) {
      final angle = (i / 6) * 2 * pi;
      final x2 = cx + cos(angle) * r;
      final y2 = cy + sin(angle) * r;
      p.strokeWidth = 1.2;
      p.color = color.withValues(alpha: 0.5 + (i % 2) * 0.4);
      c.drawLine(Offset(cx, cy), Offset(x2, y2), p);
    }
    p.color = color;
    p.strokeWidth = 1.8;
    c.drawCircle(Offset(cx, cy), r, p);
  }

  void _ripple(Canvas c, Size s, Paint p, double cy, double w) {
    p.style = PaintingStyle.stroke;
    final cx = w / 2;
    for (int i = 1; i <= 4; i++) {
      final r = min(w, s.height) * 0.1 * i;
      p.strokeWidth = 2.5 - i * 0.4;
      p.color = color.withValues(alpha: (1.0 - i * 0.2).clamp(0.1, 1.0));
      c.drawCircle(Offset(cx, cy), r, p);
    }
    p.color = color;
    p.strokeWidth = 1.8;
    // Center dot
    p.style = PaintingStyle.fill;
    c.drawCircle(Offset(cx, cy), 3, p);
  }

  // ── New Preview Methods ──────────────────────────────────────────────

  void _kaleidoscope(Canvas c, Size s, Paint p, double cy, double w) {
    p.style = PaintingStyle.fill;
    final cx = w / 2;
    const sides = 6;
    final maxR = min(w, s.height) * 0.25;

    for (int i = 0; i < sides; i++) {
      final angle = (i / sides) * 2 * pi;
      final path = Path();
      const points = 6;
      for (int j = 0; j <= points; j++) {
        final a = angle + (j / points) * (2 * pi / sides);
        final r = maxR * (0.4 + 0.4 * sin(j / points * pi));
        final x = cx + cos(a) * r;
        final y = cy + sin(a) * r;
        if (j == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      c.drawPath(path, p..color = color.withValues(alpha: 0.6));
    }

    for (int ring = 0; ring < 2; ring++) {
      p.style = PaintingStyle.stroke;
      p.strokeWidth = 2.0;
      final ringR = maxR * (0.5 + ring * 0.3);
      c.drawCircle(Offset(cx, cy), ringR, p);
    }
  }

  void _burst(Canvas c, Size s, Paint p, double cy, double w) {
    p.style = PaintingStyle.fill;
    final cx = w / 2;
    const particles = 16;
    final maxR = min(w, s.height) * 0.25;

    for (int i = 0; i < particles; i++) {
      final angle = (i / particles) * 2 * pi;
      final distance = maxR * 0.7;
      final x = cx + cos(angle) * distance;
      final y = cy + sin(angle) * distance;
      c.drawCircle(Offset(x, y), 3.0, p..color = color);
    }

    c.drawCircle(Offset(cx, cy), 5.0, p..color = color.withValues(alpha: 0.8));
  }

  void _waveStack(Canvas c, Size s, Paint p, double cy, double w) {
    p.style = PaintingStyle.stroke;
    const layers = 3;

    for (int layer = 0; layer < layers; layer++) {
      final offset = (layer / layers) * 15.0;
      final path = Path();

      for (double x = 0; x <= w; x += 2) {
        final t = x / w;
        final wave = sin(t * 3 * pi) * s.height * 0.15;
        final y = cy - offset + (layer.isEven ? 1 : -1) * wave;

        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      p.strokeWidth = 1.5 + layer * 0.3;
      p.color = color.withValues(alpha: (0.8 - layer * 0.15));
      c.drawPath(path, p);
    }
  }

  void _mandala(Canvas c, Size s, Paint p, double cy, double w) {
    final cx = w / 2;
    const layers = 3;
    const petals = 8;

    for (int layer = 0; layer < layers; layer++) {
      final layerR = w * 0.15 * (1.0 + layer * 0.3);

      for (int petal = 0; petal < petals; petal++) {
        final angle = (petal / petals) * 2 * pi;
        final x = cx + cos(angle) * layerR;
        final y = cy + sin(angle) * layerR;

        p.style = PaintingStyle.fill;
        c.drawCircle(Offset(x, y), 2.0 + layer, p..color = color);
      }

      p.style = PaintingStyle.stroke;
      p.strokeWidth = 1.2;
      c.drawCircle(Offset(cx, cy), layerR, p);
    }
  }

  void _equalizerPreview(Canvas c, Size s, Paint p, double w) {
    p.style = PaintingStyle.fill;
    const bandCount = 12;
    final bw = w / bandCount;
    final cy = s.height / 2;

    for (int i = 0; i < bandCount; i++) {
      final intensity = (sin(i * pi / bandCount) * 0.7 + 0.3).clamp(0.2, 1.0);
      final bh = s.height * 0.6 * intensity;
      final x = i * bw + bw / 2;

      p.color = HSVColor.fromAHSV(1.0, (i / bandCount) * 360, 1.0, 1.0).toColor();
      c.drawRect(
        Rect.fromLTWH(x - bw * 0.35, cy - bh / 2, bw * 0.7, bh),
        p,
      );
    }
  }

  void _beatPulse(Canvas c, Size s, Paint p, double cy, double w) {
    final cx = w / 2;
    p.style = PaintingStyle.fill;
    // Core
    c.drawCircle(Offset(cx, cy), s.height * 0.15, p..color = color);
    // Rings
    p.style = PaintingStyle.stroke;
    for (int i = 1; i <= 3; i++) {
      p.strokeWidth = 1.8 - i * 0.4;
      p.color = color.withValues(alpha: (1.0 - i * 0.25).clamp(0.1, 1.0));
      c.drawCircle(Offset(cx, cy), s.height * (0.15 + i * 0.1), p);
    }
  }

  @override
  bool shouldRepaint(covariant StylePreviewPainter old) =>
      old.style != style || old.color != color;
}
