import 'dart:math';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DefaultAlbumArt — a fully painted placeholder, no asset file required.
// Draws a vinyl-record-style disc with a music note and gradient rings.
// ─────────────────────────────────────────────────────────────────────────────
class DefaultAlbumArt extends StatelessWidget {
  final double size;
  final BorderRadius? borderRadius;
  final String? title;

  const DefaultAlbumArt({
    super.key,
    this.size = 52,
    this.borderRadius,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    Widget art = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _VinylPainter(title ?? 'Unknown')),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: art);
    }
    return art;
  }
}

class _VinylPainter extends CustomPainter {
  final String seed;

  _VinylPainter(this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = min(cx, cy);

    // Generate a pseudo-random color based on the seed string
    int hash = seed.hashCode;
    final r1 = (hash & 0xFF0000) >> 16;
    final g1 = (hash & 0x00FF00) >> 8;
    final b1 = (hash & 0x0000FF);
    
    // Create a dark but colorful base color
    final baseColor = Color.fromARGB(255, (r1 % 100) + 20, (g1 % 100) + 20, (b1 % 100) + 40);
    final darkColor = Color.fromARGB(255, (r1 % 50) + 10, (g1 % 50) + 10, (b1 % 50) + 20);

    // ── Background gradient ──────────────────────────────────────────────
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          baseColor,
          darkColor,
          const Color(0xFF0F0F1A),
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r, bgPaint);

    // ── Vinyl grooves (concentric rings) ─────────────────────────────────
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    const grooveCount = 6;
    for (int i = 1; i <= grooveCount; i++) {
      final gr = r * (0.35 + i * 0.09);
      if (gr >= r) break;
      final opacity = 0.08 + (i / grooveCount) * 0.12;
      groovePaint.color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(Offset(cx, cy), gr, groovePaint);
    }

    // ── Colored accent ring ───────────────────────────────────────────────
    final accentR = (hash % 200) + 55;
    final accentG = ((hash >> 8) % 200) + 55;
    final accentB = ((hash >> 16) % 200) + 55;
    final accentColor1 = Color.fromARGB(255, accentR, accentG, accentB);
    final accentColor2 = Color.fromARGB(255, 255 - accentR, 255 - accentG, 255 - accentB);

    final accentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..shader = SweepGradient(
        colors: [
          accentColor1,
          accentColor2,
          const Color(0xFFB24BF3),
          accentColor1,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.72));
    canvas.drawCircle(Offset(cx, cy), r * 0.72, accentPaint);

    // ── Inner dark disc ───────────────────────────────────────────────────
    final innerPaint = Paint()
      ..color = const Color(0xFF111120);
    canvas.drawCircle(Offset(cx, cy), r * 0.38, innerPaint);

    // ── Center hole ───────────────────────────────────────────────────────
    final holePaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF3A3A5C), Color(0xFF1A1A2E)],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.12));
    canvas.drawCircle(Offset(cx, cy), r * 0.12, holePaint);

    // ── Music note icon ───────────────────────────────────────────────────
    _drawMusicNote(canvas, cx, cy, r * 0.28);
  }

  void _drawMusicNote(Canvas canvas, double cx, double cy, double scale) {
    final notePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    // Stem
    final stemRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + scale * 0.18, cy - scale * 0.9,
          scale * 0.18, scale * 0.9),
      Radius.circular(scale * 0.09),
    );
    canvas.drawRRect(stemRect, notePaint);

    // Note head (filled oval)
    canvas.save();
    canvas.translate(cx, cy + scale * 0.05);
    canvas.rotate(-0.4);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset.zero, width: scale * 0.52, height: scale * 0.38),
      notePaint,
    );
    canvas.restore();

    // Flag on stem
    final flagPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * 0.14
      ..strokeCap = StrokeCap.round;

    final flagPath = Path()
      ..moveTo(cx + scale * 0.36, cy - scale * 0.9)
      ..cubicTo(
        cx + scale * 0.9, cy - scale * 0.7,
        cx + scale * 0.9, cy - scale * 0.4,
        cx + scale * 0.36, cy - scale * 0.3,
      );
    canvas.drawPath(flagPath, flagPaint);
  }

  @override
  bool shouldRepaint(covariant _VinylPainter oldDelegate) {
    return oldDelegate.seed != seed;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AlbumArtImage — drop-in replacement for Image.network with album art.
// • Shows the real image when available and loads successfully.
// • Falls back to DefaultAlbumArt on null URL, empty URL, or load error.
// • Never shows a broken image or a grey box.
// ─────────────────────────────────────────────────────────────────────────────
class AlbumArtImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final String? title;

  const AlbumArtImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.title,
  });

  bool get _hasUrl {
    if (imageUrl == null || imageUrl!.trim().isEmpty) return false;
    final lowerUrl = imageUrl!.toLowerCase();
    // Jiosaavn and other APIs often return a default image URL when art is missing.
    // We want to intercept those and use our custom DefaultAlbumArt instead.
    if (lowerUrl.contains('default') || lowerUrl.contains('placeholder') || lowerUrl.contains('nocover')) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final size = width ?? height ?? 52.0;

    Widget content;

    if (_hasUrl) {
      content = Image.network(
        imageUrl!,
        width: width,
        height: height,
        fit: fit,
        // Show default while loading
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return DefaultAlbumArt(
            size: size,
            borderRadius: borderRadius,
          );
        },
        errorBuilder: (_, __, ___) => DefaultAlbumArt(
          size: size,
          borderRadius: borderRadius,
        ),
      );
    } else {
      content = DefaultAlbumArt(size: size, borderRadius: borderRadius);
    }

    if (borderRadius != null && _hasUrl) {
      return ClipRRect(borderRadius: borderRadius!, child: content);
    }
    return content;
  }
}
