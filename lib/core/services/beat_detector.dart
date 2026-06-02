import 'package:just_audio/just_audio.dart';
import 'dart:async';
import 'dart:math' as math;

class BeatDetector {
  final AudioPlayer audioPlayer;
  late StreamSubscription<Duration> _positionSubscription;
  final List<double> frequencies = List<double>.filled(64, 0.0);
  double beatIntensity = 0.0;
  bool isPlaying = false;

  final _beatStreamController = StreamController<double>.broadcast();
  Stream<double> get beatStream => _beatStreamController.stream;

  final _freqStreamController =
      StreamController<List<double>>.broadcast();
  Stream<List<double>> get frequencyStream => _freqStreamController.stream;

  BeatDetector({required this.audioPlayer}) {
    _initializeListeners();
  }

  void _initializeListeners() {
    audioPlayer.playerStateStream.listen((state) {
      isPlaying = state.playing;
      if (!isPlaying) {
        beatIntensity = 0.0;
        _beatStreamController.add(beatIntensity);
      }
    });

    audioPlayer.positionStream.listen((_) {
      _updateBeatAndFrequencies();
    });
  }

  void _updateBeatAndFrequencies() {
    if (!isPlaying) {
      beatIntensity *= 0.95;
      _beatStreamController.add(beatIntensity);
      return;
    }

    // Simulate frequency data from audio
    // In production, you would use actual audio analysis
    final random = math.Random();
    for (int i = 0; i < frequencies.length; i++) {
      // Create bands that react to beat
      final isBassFreq = i < 8;
      final isMidFreq = i >= 8 && i < 32;
      final isHighFreq = i >= 32;

      double value = random.nextDouble() * 0.3;

      if (isBassFreq && beatIntensity > 0.5) {
        value += beatIntensity * 0.7;
      }
      if (isMidFreq) {
        value += random.nextDouble() * 0.5;
      }
      if (isHighFreq) {
        value += random.nextDouble() * 0.3;
      }

      frequencies[i] = (frequencies[i] * 0.7 + value * 0.3).clamp(0.0, 1.0);
    }

    // Simulate beat detection (simple threshold-based)
    final bassAverage =
        frequencies.sublist(0, 8).reduce((a, b) => a + b) / 8;
    if (bassAverage > 0.6) {
      beatIntensity = math.min(1.0, beatIntensity + 0.3);
    } else {
      beatIntensity = (beatIntensity - 0.05).clamp(0.0, 1.0);
    }

    _beatStreamController.add(beatIntensity);
    _freqStreamController.add(List<double>.from(frequencies));
  }

  void dispose() {
    _beatStreamController.close();
    _freqStreamController.close();
    _positionSubscription.cancel();
  }
}
