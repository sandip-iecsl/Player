import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../widgets/sound_wave_visualizer.dart';
import '../../core/services/beat_detector.dart';

class MusicPlayerWithVisualizer extends StatefulWidget {
  const MusicPlayerWithVisualizer({super.key});

  @override
  State<MusicPlayerWithVisualizer> createState() =>
      _MusicPlayerWithVisualizerState();
}

class _MusicPlayerWithVisualizerState extends State<MusicPlayerWithVisualizer>
    with WidgetsBindingObserver {
  late AudioPlayer audioPlayer;
  late BeatDetector beatDetector;
  double _beatIntensity = 0.0;
  List<double> _frequencies = List<double>.filled(64, 0.0);
  bool _isPlaying = false;
  bool _autoColor = true;
  Color _selectedColor = const Color(0xFF00FF41); // Default green

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAudioPlayer();
  }

  void _initializeAudioPlayer() {
    audioPlayer = AudioPlayer();
    beatDetector = BeatDetector(audioPlayer: audioPlayer);

    // Listen to beat stream
    beatDetector.beatStream.listen((intensity) {
      if (mounted) {
        setState(() {
          _beatIntensity = intensity;
        });
      }
    });

    // Listen to frequency stream
    beatDetector.frequencyStream.listen((freqs) {
      if (mounted) {
        setState(() {
          _frequencies = freqs;
        });
      }
    });

    // Listen to playback state
    audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });
  }

  Future<void> _loadAudio() async {
    try {
      // Replace with your actual audio URL or file path
      await audioPlayer.setAsset('assets/sample_song.mp3');
    } catch (e) {
      print('Error loading audio: $e');
    }
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.grey[900],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Select Bar Color',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    const Color(0xFF00FF41), // Green
                    const Color(0xFFFF006E), // Pink
                    const Color(0xFF9D4EDD), // Purple
                    const Color(0xFF3A86FF), // Blue
                    const Color(0xFFFFD60A), // Yellow
                    const Color(0xFFFF4757), // Red
                    Colors.cyan,
                    Colors.orange,
                  ]
                      .map(
                        (color) => GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedColor = color;
                            });
                            Navigator.pop(context);
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _selectedColor == color
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    beatDetector.dispose();
    audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Header with back button and controls
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white30),
                    ),
                    child: const Icon(Icons.chevron_left, color: Colors.white),
                  ),
                ),
                const Column(
                  children: [
                    Text(
                      'Now Playing',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Song Name',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: _showColorPicker,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _autoColor
                          ? Colors.white10
                          : _selectedColor.withOpacity(0.3),
                      border: Border.all(
                        color: _autoColor ? Colors.white30 : _selectedColor,
                      ),
                    ),
                    child: Icon(
                      Icons.palette,
                      color: _autoColor ? Colors.white70 : _selectedColor,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Color Mode Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _autoColor = true;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _autoColor
                                ? const Color(0xFF00FF41)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        'Auto Colors',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _autoColor
                              ? const Color(0xFF00FF41)
                              : Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _autoColor = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: !_autoColor
                                ? const Color(0xFF00FF41)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        'Manual Color',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: !_autoColor
                              ? const Color(0xFF00FF41)
                              : Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Visualizer at the top
          Expanded(
            flex: 2,
            child: Center(
              child: SoundWaveVisualizer(
                height: 300,
                width: double.infinity,
                frequencies: _frequencies,
                beatIntensity: _beatIntensity,
                isPlaying: _isPlaying,
                barColor: _autoColor ? null : _selectedColor,
                autoColor: _autoColor,
              ),
            ),
          ),
          // Controls at the bottom
          Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Play/Pause Button
                GestureDetector(
                  onTap: () async {
                    if (_isPlaying) {
                      await audioPlayer.pause();
                    } else {
                      if (audioPlayer.duration == null) {
                        await _loadAudio();
                      }
                      await audioPlayer.play();
                    }
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF00FF41),
                          const Color(0xFF00FF41).withOpacity(0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FF41).withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.black,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Progress Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: StreamBuilder<Duration>(
                    stream: audioPlayer.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final duration = audioPlayer.duration ?? Duration.zero;

                      return Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: duration.inMilliseconds > 0
                                  ? position.inMilliseconds /
                                      duration.inMilliseconds
                                  : 0,
                              minHeight: 4,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation(
                                Color(0xFF00FF41),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
