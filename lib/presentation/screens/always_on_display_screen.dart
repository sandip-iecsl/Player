import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import '../providers/audio_provider.dart';
import '../../data/services/always_on_display_service.dart';
import '../../domain/entities/song.dart';

class AlwaysOnDisplayScreen extends ConsumerStatefulWidget {
  const AlwaysOnDisplayScreen({super.key});

  @override
  ConsumerState<AlwaysOnDisplayScreen> createState() => _AlwaysOnDisplayScreenState();
}

class _AlwaysOnDisplayScreenState extends ConsumerState<AlwaysOnDisplayScreen> {
  late Timer _timeTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
    
    // Hide system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Force portrait
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    _timeTimer.cancel();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(currentSongProvider).value;
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final position = ref.watch(currentPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(currentDurationProvider).value ?? 
                    currentSong?.duration ?? 
                    const Duration(seconds: 1);
    final audioService = ref.watch(audioServiceProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.pop(context), // Exit AOD on tap
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Minimal Clock
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('HH:mm').format(_now),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 80,
                      fontWeight: FontWeight.w200,
                    ),
                  ),
                  Text(
                    DateFormat('EEEE, MMM d').format(_now),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 100),
                  
                  // Music Controls
                  if (currentSong != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: AODMusicControlsWidget(
                        title: currentSong.title,
                        artist: currentSong.artist,
                        albumArt: currentSong.albumArt,
                        isPlaying: isPlaying,
                        position: position,
                        duration: duration,
                        onPlayPause: () => isPlaying ? audioService.pause() : audioService.play(),
                        onNext: () => audioService.skipToNext(),
                        onPrevious: () => audioService.skipToPrevious(),
                      ),
                    ),
                ],
              ),
            ),
            
            // Exit Hint
            const Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Double tap to exit',
                  style: TextStyle(color: Colors.white10, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
