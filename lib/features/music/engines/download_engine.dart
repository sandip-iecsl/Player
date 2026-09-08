import '../../../core/kernel/i_engine.dart';

class DownloadEngine implements IEngine {
  static final DownloadEngine _instance = DownloadEngine._internal();
  factory DownloadEngine() => _instance;
  DownloadEngine._internal();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start() async {}

  Future<void> downloadSong(String trackId) async {
    // Proxies download triggers to existing DownloadService
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
