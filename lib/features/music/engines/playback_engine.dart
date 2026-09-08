import '../../../core/kernel/i_engine.dart';

class PlaybackEngine implements IEngine {
  static final PlaybackEngine _instance = PlaybackEngine._internal();
  factory PlaybackEngine() => _instance;
  PlaybackEngine._internal();

  bool _isPlaying = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start() async {}

  Future<void> playTrack(String trackId) async {
    _isPlaying = true;
  }

  Future<void> pausePlayback() async {
    _isPlaying = false;
  }

  bool get isPlaying => _isPlaying;

  @override
  Future<void> pause() async {
    await pausePlayback();
  }

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    _isPlaying = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
