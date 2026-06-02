import 'package:flutter/material.dart';

class AppStrings {
  // App
  static const String appName = 'Aura Player';
  static const String appTagline = 'Vibe with Music';

  // Navigation
  static const String home = 'Home';
  static const String search = 'Search';
  static const String library = 'Library';
  static const String settings = 'Settings';

  // Sections
  static const String trendingNow = 'Trending Now';
  static const String globalCharts = 'Global Charts';
  static const String recentlyPlayed = 'Recently Played';
  static const String favorites = 'Favorites';

  // Playback
  static const String nowPlaying = 'Now Playing';
  static const String play = 'Play';
  static const String pause = 'Pause';
  static const String skipNext = 'Skip Next';
  static const String skipPrevious = 'Skip Previous';

  // Settings
  static const String darkMode = 'Dark Mode';
  static const String lightMode = 'Light Mode';
  static const String theme = 'Theme';
  static const String about = 'About';

  // Errors
  static const String errorLoadingMusic = 'Oops! Can\'t load music';
  static const String errorPlayingTrack = 'Can\'t play this track';
  static const String noInternetConnection = 'No internet, bro';
  static const String tryAgain = 'Try Again';
}

/// Gen-Z focused logo widget
class AuraPlayerLogo extends StatelessWidget {
  final double size;
  final bool animated;

  const AuraPlayerLogo({
    super.key,
    this.size = 60,
    this.animated = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: OverflowBox(
              minWidth: size * 1.4,
              maxWidth: size * 1.4,
              minHeight: size * 1.4,
              maxHeight: size * 1.4,
              child: Image.asset(
                'assets/logo/logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _SandipBranding(),
      ],
    );
  }
}

class _SandipBranding extends StatefulWidget {
  @override
  State<_SandipBranding> createState() => _SandipBrandingState();
}

class _SandipBrandingState extends State<_SandipBranding>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Text(
        'Created by Sandip',
        style: TextStyle(
          color: const Color(0xFF1DB954),
          fontSize: 8,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          shadows: [
            Shadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 2,
                offset: const Offset(0, 1)),
          ],
        ),
      ),
    );
  }
}
