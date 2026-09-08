import '../../core/shared/metrics/metrics_engine.dart';

class PlaybackDomainService {
  static final PlaybackDomainService _instance = PlaybackDomainService._internal();
  factory PlaybackDomainService() => _instance;
  PlaybackDomainService._internal();

  /// Logs playback metrics whenever a track begins playing.
  void trackPlaybackStart(String trackId) {
    final startTime = DateTime.now();
    // Simulate recording start metrics
    final latency = DateTime.now().difference(startTime).inMilliseconds;
    MetricsEngine().recordPlaybackStart(latency);
  }
}
