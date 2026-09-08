import 'i_engine.dart';

class EngineCoordinator {
  static final EngineCoordinator _instance = EngineCoordinator._internal();
  factory EngineCoordinator() => _instance;
  EngineCoordinator._internal();

  final List<IEngine> _phase1Engines = [];
  final List<IEngine> _phase2Engines = [];
  final List<IEngine> _phase3Engines = [];
  final List<IEngine> _phase4Engines = [];

  bool _initialized = false;
  bool _running = false;

  /// Registers an engine in a specific phase.
  void registerEngine(IEngine engine, int phase) {
    switch (phase) {
      case 1:
        _phase1Engines.add(engine);
        break;
      case 2:
        _phase2Engines.add(engine);
        break;
      case 3:
        _phase3Engines.add(engine);
        break;
      case 4:
        _phase4Engines.add(engine);
        break;
      default:
        throw Exception('Invalid coordinator phase: $phase');
    }
  }

  /// Ordered initialization of engines (Phase 1 -> Phase 2 -> Phase 3 -> Phase 4).
  Future<void> initialize() async {
    if (_initialized) return;

    for (final engine in _phase1Engines) {
      await engine.initialize();
    }
    for (final engine in _phase2Engines) {
      await engine.initialize();
    }
    for (final engine in _phase3Engines) {
      await engine.initialize();
    }
    for (final engine in _phase4Engines) {
      await engine.initialize();
    }

    _initialized = true;
  }

  /// Ordered start of engines.
  Future<void> start() async {
    if (_running) return;

    for (final engine in _phase1Engines) {
      await engine.start();
    }
    for (final engine in _phase2Engines) {
      await engine.start();
    }
    for (final engine in _phase3Engines) {
      await engine.start();
    }
    for (final engine in _phase4Engines) {
      await engine.start();
    }

    _running = true;
  }

  /// Pause all engines.
  Future<void> pause() async {
    for (final engine in _phase4Engines) {
      await engine.pause();
    }
    for (final engine in _phase3Engines) {
      await engine.pause();
    }
    for (final engine in _phase2Engines) {
      await engine.pause();
    }
    for (final engine in _phase1Engines) {
      await engine.pause();
    }
  }

  /// Resume all engines.
  Future<void> resume() async {
    for (final engine in _phase1Engines) {
      await engine.resume();
    }
    for (final engine in _phase2Engines) {
      await engine.resume();
    }
    for (final engine in _phase3Engines) {
      await engine.resume();
    }
    for (final engine in _phase4Engines) {
      await engine.resume();
    }
  }

  /// Stop all engines.
  Future<void> stop() async {
    for (final engine in _phase4Engines) {
      await engine.stop();
    }
    for (final engine in _phase3Engines) {
      await engine.stop();
    }
    for (final engine in _phase2Engines) {
      await engine.stop();
    }
    for (final engine in _phase1Engines) {
      await engine.stop();
    }
    _running = false;
  }

  /// Dispose all engines and clear coordinator state.
  Future<void> dispose() async {
    await stop();

    for (final engine in _phase4Engines) {
      await engine.dispose();
    }
    for (final engine in _phase3Engines) {
      await engine.dispose();
    }
    for (final engine in _phase2Engines) {
      await engine.dispose();
    }
    for (final engine in _phase1Engines) {
      await engine.dispose();
    }

    _phase1Engines.clear();
    _phase2Engines.clear();
    _phase3Engines.clear();
    _phase4Engines.clear();
    _initialized = false;
  }

  /// Restart all engines in the coordinator.
  Future<void> restart() async {
    await dispose();
    await initialize();
    await start();
  }
}
