import '../../../core/kernel/i_engine.dart';

class QueueEngine implements IEngine {
  static final QueueEngine _instance = QueueEngine._internal();
  factory QueueEngine() => _instance;
  QueueEngine._internal();

  final List<String> _queue = [];
  int _currentIndex = -1;

  List<String> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;

  void addTrack(String trackId) {
    _queue.add(trackId);
  }

  void removeTrack(String trackId) {
    _queue.remove(trackId);
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    clearQueue();
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
