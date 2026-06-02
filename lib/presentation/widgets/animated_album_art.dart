import 'package:flutter/material.dart';
import 'default_album_art.dart';

class AnimatedAlbumArt extends StatefulWidget {
  final String? imageUrl;
  final bool isPlaying;
  final double size;

  const AnimatedAlbumArt({
    super.key,
    this.imageUrl,
    this.isPlaying = false,
    this.size = 200,
  });

  @override
  State<AnimatedAlbumArt> createState() => _AnimatedAlbumArtState();
}

class _AnimatedAlbumArtState extends State<AnimatedAlbumArt>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    if (widget.isPlaying) _controller.repeat();
  }

  @override
  void didUpdateWidget(AnimatedAlbumArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: AlbumArtImage(
          imageUrl: widget.imageUrl,
          width: widget.size,
          height: widget.size,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
