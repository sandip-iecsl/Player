import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../providers/visualizer_provider.dart';

class EnhancedVisualizerPainter extends CustomPainter {
  final List<double> heights;
  final double animationValue;
  final Color primaryColor;
  final VisualizerStyle style;
  final double pulse;

  EnhancedVisualizerPainter({
    required this.heights,
    required this.animationValue,
    required this.primaryColor,
    required this.style,
    required this.pulse,
  });

  // ── Shared helpers ────────────────────────────────────────────────────

  double _si(double t) {
    final idx = t * (heights.length - 1);
    final i = idx.floor().clamp(0, heights.length - 2);
    final f = idx - i;
    return ui.lerpDouble(heights[i], heights[i + 1], f) ?? 0.0;
  }

  double get _avg => heights.reduce((a, b) => a + b) / heights.length;

  Shader _gradient(Rect rect) {
    final hsv = HSVColor.fromColor(primaryColor);
    final c0 = hsv.withValue(1.0).withSaturation(1.0).toColor();
    final c1 = hsv.withHue((hsv.hue + 60) % 360).withValue(1.0).toColor();
    final c2 = hsv.withHue((hsv.hue + 120) % 360).withValue(1.0).toColor();
    return LinearGradient(
      colors: [
        c0.withValues(alpha: 0.05),
        c0.withValues(alpha: 0.55),
        c1.withValues(alpha: 0.85),
        c2,
        Colors.white,
        c2,
        c1.withValues(alpha: 0.85),
        c0.withValues(alpha: 0.55),
        c0.withValues(alpha: 0.05),
      ],
      stops: const [0.0, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 1.0],
    ).createShader(rect);
  }

  // ── Entry point ───────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final w = size.width;
    final rect = Rect.fromLTWH(0, 0, w, size.height);
    final grad = _gradient(rect);
    final phase = animationValue * (1.0 + pulse * 3.0);

    final p = Paint()
      ..shader = grad
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = BlendMode.screen;

    switch (style) {
      case VisualizerStyle.enhancedBars:
        _enhancedBars(canvas, size, p, cy, w, phase);
      case VisualizerStyle.enhancedGlowingBars:
        _glowingBars(canvas, size, p, cy, w, phase);
      case VisualizerStyle.liquidWave:
        _liquidWave(canvas, size, p, cy, w, phase);
      case VisualizerStyle.oscilloscopeWave:
        _oscilloscopeWave(canvas, size, p, cy, w, phase);
      case VisualizerStyle.neonRings:
        _neonRings(canvas, size, p, cy, w, phase);
      case VisualizerStyle.radialBeat:
        _radialBeat(canvas, size, p, cy, w, phase);
      case VisualizerStyle.beatPulseWave:
        _beatPulseWave(canvas, size, p, cy, w, phase);
      case VisualizerStyle.tunnelRings:
        _tunnelRings(canvas, size, p, cy, w, phase);
      case VisualizerStyle.fireWave:
        _fireWave(canvas, size, p, cy, w, phase);
      case VisualizerStyle.morphBlob:
        _morphBlob(canvas, size, p, cy, w, phase);
      case VisualizerStyle.auroraCurtain:
        _auroraCurtain(canvas, size, p, cy, w, phase);
      case VisualizerStyle.plasmaOrb:
        _plasmaOrb(canvas, size, p, cy, w, phase);
      case VisualizerStyle.beatRipple:
        _beatRipple(canvas, size, p, cy, w, phase);
      case VisualizerStyle.kaleidoscope:
        _kaleidoscope(canvas, size, p, cy, w, phase);
      case VisualizerStyle.spectrumBurst:
        _spectrumBurst(canvas, size, p, cy, w, phase);
      case VisualizerStyle.waveStack:
        _waveStack(canvas, size, p, cy, w, phase);
      case VisualizerStyle.mandalaPattern:
        _mandalaPattern(canvas, size, p, cy, w, phase);
      case VisualizerStyle.equalizerBands:
        _equalizerBands(canvas, size, p, cy, w, phase);
      case VisualizerStyle.beatPulse:
        _beatPulse(canvas, size, p, cy, w, phase);
    }
  }

  // ── 1. Enhanced Bars ─────────────────────────────────────────────────

  void _enhancedBars(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.fill;
    const n = 60;
    final bw = w / n;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final intensity = _si(t);
      final env = (pow(sin(t * pi), 0.4) + sin(ph * 4 + i * 0.3) * 0.1).clamp(0.0, 2.0);
      final bh = (s.height * 0.8) * intensity * env;
      if (bh < 2) continue;
      final x = i * bw + bw / 2;
      final rr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, s.height - bh / 2), width: bw * 0.78, height: bh),
        Radius.circular(bw * 0.2),
      );
      c.drawRRect(rr, p);
    }
  }

  // ── 2. Liquid Wave ───────────────────────────────────────────────────

  void _liquidWave(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.fill;
    final top = Path()..moveTo(0, cy);
    final bot = Path()..moveTo(0, cy);
    for (double x = 0; x <= w; x += 2) {
      final t = x / w;
      final intensity = _si(t);
      final wave = sin(t * 8 * pi - ph * 12 * pi) * 0.3
          + sin(t * 16 * pi - ph * 8 * pi) * 0.15
          + sin(t * 32 * pi + ph * 20 * pi) * 0.05;
      final env = pow(sin(t * pi), 0.6);
      final h = (s.height * 0.4) * intensity * env * (1.0 + wave);
      top.lineTo(x, cy - h);
      bot.lineTo(x, cy + h);
    }
    top..lineTo(w, cy)..lineTo(0, cy);
    bot..lineTo(w, cy)..lineTo(0, cy);
    c.drawPath(top, p);
    c.drawPath(bot, p);
  }

  // ── 3. Neon Rings ────────────────────────────────────────────────────

  void _neonRings(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.stroke;
    final cx = w / 2;
    final maxR = min(w * 0.4, s.height * 0.4);
    final avg = _avg;
    for (int ring = 0; ring < 8; ring++) {
      final rt = ring / 7.0;
      final intensity = _si(rt);
      final r = maxR * (0.2 + rt * 0.8) * (0.8 + intensity * 0.4 + avg * 0.2);
      final rot = ph * (1.0 + ring * 0.2);
      const segs = 32;
      for (int seg = 0; seg < segs; seg++) {
        final a1 = (seg / segs) * 2 * pi + rot;
        final a2 = ((seg + 1) / segs) * 2 * pi + rot;
        final si = intensity * (0.5 + sin(a1 * 4 + ph * 8) * 0.5);
        if (si < 0.2) continue;
        p.strokeWidth = 2.0 + si * 6.0;
        final o1 = Offset(cx + cos(a1) * r, cy + sin(a1) * r);
        final o2 = Offset(cx + cos(a2) * r, cy + sin(a2) * r);
        c.drawLine(o1, o2, p);
      }
    }
  }

  // ── 4. Enhanced Glowing Bars ─────────────────────────────────────────

  void _glowingBars(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.stroke;
    const n = 50;
    final bw = w / n;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final intensity = _si(t);
      final env = pow(sin(t * pi), 0.5);
      final bh = (s.height * 0.45) * intensity * env;
      if (bh < 3) continue;
      final x = i * bw + bw / 2;
      p.strokeWidth = 3;
      c.drawLine(Offset(x, cy - bh), Offset(x, cy + bh), p);
    }
  }

  // ── 5. Beat Pulse Wave ───────────────────────────────────────────────

  void _beatPulseWave(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    final avg = _avg;
    final ps = 0.8 + avg * 0.4;
    // Expanding rings
    for (int ring = 0; ring < 5; ring++) {
      final phase = (ph * 6.0 + ring * 0.15) % 1.0;
      final r = w * 0.25 * (phase + ring * 0.15);
      final opacity = (1.0 - phase) * 0.8 * avg;
      p.style = PaintingStyle.stroke;
      p.strokeWidth = 3.0 + (1.0 - phase) * 8.0;
      c.drawCircle(Offset(w / 2, cy), r, p..color = primaryColor.withValues(alpha: opacity));
    }
    // Bars underneath
    const n = 40;
    final bw = w / n;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final intensity = _si(t);
      final env = pow(sin(t * pi), 0.5);
      final bh = (s.height * 0.35) * intensity * env * ps;
      if (bh < 2) continue;
      final x = i * bw + bw / 2;
      p.style = PaintingStyle.stroke;
      p.strokeWidth = bw * 0.7;
      c.drawLine(Offset(x, cy - bh), Offset(x, cy + bh), p);
    }
  }

  // ── 6. Oscilloscope Wave ─────────────────────────────────────────────

  void _oscilloscopeWave(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 3.0;
    final avg = _avg;

    // Top wave
    final topPath = Path();
    // Bottom mirror wave
    final botPath = Path();

    for (double x = 0; x <= w; x += 1.5) {
      final t = x / w;
      final intensity = _si(t);
      // Sharp oscilloscope response — snaps hard to beat
      final snap = 1.0 + avg * 2.0;
      final wave = sin(t * 10 * pi - ph * 16 * pi) * intensity * snap;
      final h = (s.height * 0.38) * intensity * (1.0 + wave * 0.4);

      if (x == 0) {
        topPath.moveTo(x, cy - h);
        botPath.moveTo(x, cy + h);
      } else {
        topPath.lineTo(x, cy - h);
        botPath.lineTo(x, cy + h);
      }
    }

    p.strokeWidth = 2.5;
    c.drawPath(topPath, p);
    c.drawPath(botPath, p);

    // Center baseline
    p.strokeWidth = 1.0;
    p.color = primaryColor.withValues(alpha: 0.3);
    c.drawLine(Offset(0, cy), Offset(w, cy), p);
  }

  // ── 7. Radial Beat ───────────────────────────────────────────────────

  void _radialBeat(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.stroke;
    final cx = w / 2;
    final maxR = min(w * 0.35, s.height * 0.35);
    final avg = _avg;
    for (int ray = 0; ray < 24; ray++) {
      final angle = (ray / 24.0) * 2 * pi + ph * 0.5;
      final intensity = _si(ray / 24.0) * avg;
      final r = maxR * (0.5 + intensity * 0.5);
      p.strokeWidth = 2.0 + intensity * 8.0;
      c.drawLine(Offset(cx, cy), Offset(cx + cos(angle) * r, cy + sin(angle) * r), p);
    }
    p.strokeWidth = 3;
    c.drawCircle(Offset(cx, cy), maxR * 0.3 * (1 + avg * 0.5), p);
  }

  // ── 9. Tunnel Rings ─────────────────────────────────────────────────

  void _tunnelRings(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.stroke;
    final cx = w / 2;
    final avg = _avg;
    const ringCount = 10;
    for (int i = 0; i < ringCount; i++) {
      // Each ring zooms from small to large and fades out
      final progress = ((ph * 0.8 + i / ringCount) % 1.0);
      final r = min(w, s.height) * 0.5 * progress;
      final opacity = (1.0 - progress) * (0.4 + avg * 0.6);
      final intensity = _si(i / ringCount);
      p.strokeWidth = 2.0 + (1.0 - progress) * 6.0 + intensity * 4.0;
      c.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 2.2, height: r * 1.4),
        p..color = primaryColor.withValues(alpha: (opacity * 0.7).clamp(0.0, 1.0)),
      );
    }
  }

  // ── 11. Fire Wave ────────────────────────────────────────────────────

  void _fireWave(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.fill;
    const n = 80;
    final bw = w / n;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final intensity = _si(t);
      // Flicker effect
      final flicker = 0.85 + sin(ph * 30 + i * 1.7) * 0.15;
      final bh = (s.height * 0.75) * intensity * flicker;
      if (bh < 2) continue;
      final x = i * bw + bw / 2;
      // Fire gradient: yellow at base → orange → red → transparent at tip
      final fireGrad = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.yellow.withValues(alpha: 0.9),
          Colors.orange.withValues(alpha: 0.8),
          Colors.red.withValues(alpha: 0.6),
          primaryColor.withValues(alpha: 0.3),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(x - bw / 2, s.height - bh, bw, bh));
      p.shader = fireGrad;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - bw * 0.4, s.height - bh, bw * 0.8, bh),
          Radius.circular(bw * 0.3),
        ),
        p,
      );
    }
    // Restore gradient shader
    p.shader = _gradient(Rect.fromLTWH(0, 0, w, s.height));
  }

  // ── 11. Morph Blob ───────────────────────────────────────────────────

  void _morphBlob(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.fill;
    final cx = w / 2;
    final avg = _avg;
    final baseR = min(w, s.height) * (0.15 + avg * 0.12);
    const points = 64;
    final path = Path();
    for (int i = 0; i <= points; i++) {
      final angle = (i / points) * 2 * pi;
      final t = (i / points);
      final intensity = _si(t);
      // Organic deformation using multiple sine waves
      final deform = 1.0
          + sin(angle * 3 + ph * 4) * 0.2 * intensity
          + sin(angle * 5 - ph * 6) * 0.15 * intensity
          + sin(angle * 7 + ph * 3) * 0.1 * avg;
      final r = baseR * deform;
      final x = cx + cos(angle) * r;
      final y = cy + sin(angle) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    c.drawPath(path, p);
    // Outer ring
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 2.0 + avg * 4.0;
    c.drawPath(path, p);
  }

  // ── 12. Aurora Curtain ───────────────────────────────────────────────
  // Vertical light curtains that ripple and pulse with every beat

  void _auroraCurtain(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    const cols = 40;
    final bw = w / cols;
    final avg = _avg;

    for (int i = 0; i < cols; i++) {
      final t = i / (cols - 1);
      final intensity = _si(t);
      // Ripple offset — each column shifts vertically with the beat
      final ripple = sin(ph * 8 * pi + i * 0.4) * intensity * s.height * 0.12;
      final bh = (s.height * 0.85) * intensity * (0.5 + avg * 0.5);
      if (bh < 4) continue;

      final x = i * bw;
      final top = cy - bh / 2 + ripple;

      // Aurora gradient: transparent → color → white → color → transparent
      final grad = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withValues(alpha: 0.0),
          primaryColor.withValues(alpha: 0.5 + intensity * 0.4),
          Colors.white.withValues(alpha: 0.6 + intensity * 0.3),
          primaryColor.withValues(alpha: 0.5 + intensity * 0.4),
          primaryColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(x, top, bw, bh));

      p.style = PaintingStyle.fill;
      p.shader = grad;
      c.drawRect(Rect.fromLTWH(x + 0.5, top, bw - 1, bh), p);
    }
    // Restore gradient shader
    p.shader = _gradient(Rect.fromLTWH(0, 0, w, s.height));
  }

  // ── 13. Plasma Orb ───────────────────────────────────────────────────
  // Glowing plasma ball with electric arcs driven by beat intensity

  void _plasmaOrb(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.stroke;
    final cx = w / 2;
    final avg = _avg;
    final maxR = min(w * 0.32, s.height * 0.38);
    final orbR = maxR * (0.3 + avg * 0.25);

    // ── Outer glow rings ──
    for (int ring = 0; ring < 4; ring++) {
      final rr = orbR + ring * maxR * 0.12 * (1 + avg * 0.5);
      final opacity = (0.5 - ring * 0.1) * avg;
      p.strokeWidth = 3.0 - ring * 0.5;
      c.drawCircle(Offset(cx, cy), rr,
          p..color = primaryColor.withValues(alpha: opacity.clamp(0.0, 1.0)));
    }

    // ── Electric arcs ──
    const arcCount = 12;
    for (int i = 0; i < arcCount; i++) {
      final baseAngle = (i / arcCount) * 2 * pi + ph * 3.0;
      final intensity = _si(i / arcCount);
      final arcLen = maxR * (0.4 + intensity * 0.6);

      // Jagged arc path
      final arcPath = Path();
      arcPath.moveTo(cx, cy);
      const segments = 5;
      for (int seg = 1; seg <= segments; seg++) {
        final segT = seg / segments;
        final angle = baseAngle + sin(ph * 10 + seg * 1.3) * 0.4 * intensity;
        final r = arcLen * segT;
        final jitter = (seg < segments)
            ? sin(ph * 20 + i * 3.7 + seg * 2.1) * arcLen * 0.08 * intensity
            : 0.0;
        arcPath.lineTo(
          cx + cos(angle) * r + jitter,
          cy + sin(angle) * r + jitter,
        );
      }

      p.strokeWidth = 1.5 + intensity * 3.0;
      p.color = primaryColor.withValues(alpha: 0.4 + intensity * 0.5);
      c.drawPath(arcPath, p);
    }

    // ── Core orb ──
    p.style = PaintingStyle.fill;
    c.drawCircle(Offset(cx, cy), orbR,
        p..color = primaryColor.withValues(alpha: 0.6 + avg * 0.3));
    // Bright center
    c.drawCircle(Offset(cx, cy), orbR * 0.4,
        p..color = Colors.white.withValues(alpha: 0.7 + avg * 0.2));
  }

  // ── 14. Beat Ripple ──────────────────────────────────────────────────
  // Water-ripple rings that expand from center on every beat

  void _beatRipple(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.stroke;
    final cx = w / 2;
    final avg = _avg;
    final maxR = min(w * 0.48, s.height * 0.48);

    // ── Expanding ripple rings ──
    const rippleCount = 8;
    for (int i = 0; i < rippleCount; i++) {
      // Each ring has its own phase offset so they spread out
      final progress = ((ph * 1.2 + i / rippleCount) % 1.0);
      final r = maxR * progress;
      final opacity = (1.0 - progress) * (0.5 + avg * 0.5);
      final strokeW = (1.0 - progress) * (4.0 + avg * 6.0);

      if (opacity < 0.02) continue;

      p.strokeWidth = strokeW.clamp(0.5, 10.0);
      p.color = primaryColor.withValues(alpha: opacity.clamp(0.0, 1.0));

      c.drawCircle(Offset(cx, cy), r, p);
    }

    // ── Frequency bars radiating outward ──
    const rayCount = 32;
    for (int i = 0; i < rayCount; i++) {
      final angle = (i / rayCount) * 2 * pi;
      final intensity = _si(i / rayCount);
      final innerR = maxR * 0.08;
      final outerR = maxR * (0.12 + intensity * 0.35 * (1 + avg));

      p.strokeWidth = 2.0 + intensity * 4.0;
      p.color = primaryColor.withValues(alpha: 0.5 + intensity * 0.4);
      c.drawLine(
        Offset(cx + cos(angle) * innerR, cy + sin(angle) * innerR),
        Offset(cx + cos(angle) * outerR, cy + sin(angle) * outerR),
        p,
      );
    }

    // ── Pulsing center dot ──
    p.style = PaintingStyle.fill;
    c.drawCircle(Offset(cx, cy), maxR * 0.06 * (1 + avg * 0.8),
        p..color = Colors.white.withValues(alpha: 0.8 + avg * 0.2));
  }

  // ── 15. Kaleidoscope ─────────────────────────────────────────────────
  // Symmetric mirrored mandala-like patterns rotating with beat

  void _kaleidoscope(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.fill;
    final cx = w / 2;
    final avg = _avg;
    const sides = 6; // hexagonal symmetry
    final maxR = min(w * 0.35, s.height * 0.35);

    for (int i = 0; i < sides; i++) {
      final baseAngle = (i / sides) * 2 * pi;
      
      // Inner shape
      final innerPath = Path();
      const innerPoints = 12;
      for (int j = 0; j <= innerPoints; j++) {
        final angle = baseAngle + (j / innerPoints) * (2 * pi / sides);
        final intensity = _si(j / innerPoints);
        final r = maxR * (0.2 + intensity * avg * 0.3);
        final x = cx + cos(angle) * r;
        final y = cy + sin(angle) * r;
        
        if (j == 0) {
          innerPath.moveTo(x, y);
        } else {
          innerPath.lineTo(x, y);
        }
      }
      innerPath.close();
      
      c.drawPath(innerPath, p..color = primaryColor.withValues(alpha: 0.6 + avg * 0.3));
    }

    // Outer rotating circles
    for (int ring = 0; ring < 3; ring++) {
      final ringR = maxR * (0.4 + ring * 0.2) + avg * maxR * 0.15;
      p.style = PaintingStyle.stroke;
      p.strokeWidth = 2.0 + ring * 1.0 + avg * 2.0;
      c.drawCircle(Offset(cx, cy), ringR,
          p..color = primaryColor.withValues(alpha: (0.7 - ring * 0.15) * (0.5 + avg * 0.5)));
    }
  }

  // ── 16. Spectrum Burst ───────────────────────────────────────────────
  // Particles bursting outward on strong beats

  void _spectrumBurst(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.fill;
    final cx = w / 2;
    final avg = _avg;
    const particleCount = 48;
    
    // Burst intensity based on beat
    final burstIntensity = max(0, avg - 0.3) * 1.4;
    final burstRadius = w * 0.25 * (0.3 + burstIntensity * 0.7);

    for (int i = 0; i < particleCount; i++) {
      final angle = (i / particleCount) * 2 * pi + ph * 3.0;
      final intensity = _si(i / particleCount);
      
      // Particles expand on burst
      final distance = burstRadius * (1.0 + burstIntensity * sin(ph * 15 + i * 0.3));
      final x = cx + cos(angle) * distance;
      final y = cy + sin(angle) * distance;
      
      // Particle size varies with intensity and burst
      final particleSize = 2.0 + intensity * 4.0 + burstIntensity * 3.0;
      
      c.drawCircle(Offset(x, y), particleSize,
          p..color = primaryColor.withValues(alpha: 0.6 + intensity * 0.3 + burstIntensity * 0.2));
    }

    // Center core
    c.drawCircle(Offset(cx, cy), 8.0 + avg * 6.0,
        p..color = Colors.white.withValues(alpha: 0.8));
  }

  // ── 17. Wave Stack ───────────────────────────────────────────────────
  // Stacked layered waveforms moving with beat

  void _waveStack(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.stroke;
    const layers = 5;
    final avg = _avg;
    
    for (int layer = 0; layer < layers; layer++) {
      final layerOffset = (layer / layers) * 30.0;
      final layerPhase = ph + layer * 0.3;
      final layerPath = Path();
      
      for (double x = 0; x <= w; x += 2.0) {
        final t = x / w;
        final intensity = _si(t);
        
        // Multiple oscillators with different frequencies
        final wave1 = sin(layerPhase * 8 + t * 10 * pi) * 0.4;
        final wave2 = sin(layerPhase * 5 - t * 8 * pi) * 0.3;
        final wave3 = cos(layerPhase * 3 + t * 6 * pi) * 0.2;
        
        final waveHeight = (wave1 + wave2 + wave3) * intensity * (s.height * 0.25) * (0.5 + avg);
        final yOffset = cy - layerOffset + (layer.isEven ? 1 : -1) * 15;
        
        if (x == 0) {
          layerPath.moveTo(x, yOffset + waveHeight);
        } else {
          layerPath.lineTo(x, yOffset + waveHeight);
        }
      }
      
      p.strokeWidth = 2.0 + layer * 0.5;
      final opacity = 0.8 - (layer * 0.12);
      c.drawPath(layerPath, p..color = primaryColor.withValues(alpha: opacity));
    }
  }

  // ── 18. Mandala Pattern ──────────────────────────────────────────────
  void _mandalaPattern(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    final cx = w / 2;
    final avg = _avg;
    const layers = 4;
    const petals = 8;
    
    for (int layer = 0; layer < layers; layer++) {
      final layerR = w * 0.2 * (1.0 + layer * 0.25) * (0.8 + avg * 0.4);
      
      for (int petal = 0; petal < petals; petal++) {
        final angle = (petal / petals) * 2 * pi + ph * (1.0 + layer * 0.2);
        final intensity = _si(petal / petals);
        
        // Draw petal shape
        final petalPath = Path();
        const petalSegments = 8;
        for (int seg = 0; seg <= petalSegments; seg++) {
          final segT = seg / petalSegments;
          final petalAngle = angle + (segT - 0.5) * 0.6;
          final petalR = layerR * (0.8 + intensity * 0.4 * cos(segT * pi));
          
          final x = cx + cos(petalAngle) * petalR;
          final y = cy + sin(petalAngle) * petalR;
          
          if (seg == 0) {
            petalPath.moveTo(x, y);
          } else {
            petalPath.lineTo(x, y);
          }
        }
        petalPath.close();
        
        p.style = PaintingStyle.fill;
        c.drawPath(petalPath, p..color = primaryColor.withValues(
          alpha: 0.3 + intensity * (0.3 + avg * 0.2)));
      }
      
      // Layer circle
      p.style = PaintingStyle.stroke;
      p.strokeWidth = 1.5 + avg * 2.0;
      c.drawCircle(Offset(cx, cy), layerR,
          p..color = primaryColor.withValues(alpha: 0.6));
    }
  }

  // ── 19. Equalizer Bands ──────────────────────────────────────────────
  // Frequency-separated colored bands rising with intensity

  void _equalizerBands(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.fill;
    const bandCount = 64;
    final bw = w / bandCount;
    final avg = _avg;
    
    // Color spectrum for bands
    final List<Color> spectrum = [
      const HSVColor.fromAHSV(1.0, 0.0, 1.0, 1.0).toColor(),      // Red
      const HSVColor.fromAHSV(1.0, 30.0, 1.0, 1.0).toColor(),     // Orange
      const HSVColor.fromAHSV(1.0, 60.0, 1.0, 1.0).toColor(),     // Yellow
      const HSVColor.fromAHSV(1.0, 120.0, 1.0, 1.0).toColor(),    // Green
      const HSVColor.fromAHSV(1.0, 180.0, 1.0, 1.0).toColor(),    // Cyan
      const HSVColor.fromAHSV(1.0, 240.0, 1.0, 1.0).toColor(),    // Blue
      const HSVColor.fromAHSV(1.0, 300.0, 1.0, 1.0).toColor(),    // Magenta
    ];

    for (int i = 0; i < bandCount; i++) {
      final t = i / (bandCount - 1);
      final intensity = _si(t);
      
      // Beat-responsive height with some wobble
      final wobble = sin(ph * 20 + i * 0.5) * 0.1 * intensity;
      final bh = (s.height * 0.8) * intensity * (0.3 + avg * 0.7 + wobble);
      
      if (bh < 1) continue;
      
      final x = i * bw + bw / 2;
      final colorIndex = (i % spectrum.length);
      
      // Gradient fill for each band
      final bandGrad = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          spectrum[colorIndex],
          spectrum[colorIndex].withValues(alpha: 0.5),
          spectrum[colorIndex].withValues(alpha: 0.2),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(x - bw / 2, s.height - bh, bw, bh));
      
      p.shader = bandGrad;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - bw * 0.35, s.height - bh, bw * 0.7, bh),
          Radius.circular(bw * 0.2),
        ),
        p,
      );
    }
    
    // Restore main gradient
    p.shader = _gradient(Rect.fromLTWH(0, 0, w, s.height));
  }

  // ── 20. Beat Pulse ───────────────────────────────────────────────────
  // A central "heart" that pulses with the beat, sending out shockwaves

  void _beatPulse(Canvas c, Size s, Paint p, double cy, double w, double ph) {
    p.style = PaintingStyle.fill;
    final cx = w / 2;
    final avg = _avg;
    final maxR = min(w * 0.4, s.height * 0.4);
    
    // Core pulse
    final coreR = maxR * 0.3 * (1.0 + pulse * 0.4);
    final coreGlow = RadialGradient(
      colors: [
        Colors.white,
        primaryColor,
        primaryColor.withOpacity(0.0),
      ],
    ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: coreR * 1.5));
    
    p.shader = coreGlow;
    c.drawCircle(Offset(cx, cy), coreR, p);
    
    // Expanding shockwaves
    p.style = PaintingStyle.stroke;
    p.shader = null;
    for (int i = 0; i < 4; i++) {
      final waveProgress = (ph * 1.5 + i * 0.25) % 1.0;
      final waveR = coreR + (maxR - coreR) * waveProgress;
      final opacity = (1.0 - waveProgress) * pulse;
      
      p.strokeWidth = 2.0 + (1.0 - waveProgress) * 8.0;
      p.color = primaryColor.withOpacity(opacity.clamp(0.0, 1.0));
      c.drawCircle(Offset(cx, cy), waveR, p);
    }
    
    // Beating "veins"
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * pi + ph * 0.5;
      final intensity = _si(i / 12);
      final len = coreR + intensity * maxR * 0.4 * pulse;
      
      p.strokeWidth = 2.0 + intensity * 4.0;
      p.color = primaryColor.withOpacity(0.6 * pulse);
      c.drawLine(
        Offset(cx + cos(angle) * coreR, cy + sin(angle) * coreR),
        Offset(cx + cos(angle) * len, cy + sin(angle) * len),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
