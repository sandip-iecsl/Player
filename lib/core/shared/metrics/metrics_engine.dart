import 'package:flutter/widgets.dart';
import '../../kernel/i_engine.dart';

class MetricsEngine implements IEngine {
  static final MetricsEngine _instance = MetricsEngine._internal();
  factory MetricsEngine() => _instance;
  MetricsEngine._internal();

  final Map<String, dynamic> _metrics = {
    'startup_ms': 0,
    'firestore_reads': 0,
    'firestore_writes': 0,
    'cache_hits': 0,
    'cache_misses': 0,
    'search_latency_ms': <int>[],
    'playback_start_ms': 0,
  };

  DateTime? _bootStart;

  @override
  Future<void> initialize() async {
    _bootStart = DateTime.now();
    debugPrint('[MetricsEngine] 📊 Initialized.');
  }

  @override
  Future<void> start() async {
    if (_bootStart != null) {
      final duration = DateTime.now().difference(_bootStart!).inMilliseconds;
      _metrics['startup_ms'] = duration;
      debugPrint('[MetricsEngine] 📊 Application Boot Duration: ${duration}ms');
    }
  }

  void incrementFirestoreReads() {
    _metrics['firestore_reads'] = (_metrics['firestore_reads'] as int) + 1;
  }

  void incrementFirestoreWrites(int operationsCount) {
    _metrics['firestore_writes'] = (_metrics['firestore_writes'] as int) + operationsCount;
  }

  void recordCacheHit() {
    _metrics['cache_hits'] = (_metrics['cache_hits'] as int) + 1;
  }

  void recordCacheMiss() {
    _metrics['cache_misses'] = (_metrics['cache_misses'] as int) + 1;
  }

  void recordSearchLatency(int durationMs) {
    final list = _metrics['search_latency_ms'] as List<int>;
    list.add(durationMs);
    if (list.length > 20) {
      list.removeAt(0); // sliding window
    }
  }

  void recordPlaybackStart(int durationMs) {
    _metrics['playback_start_ms'] = durationMs;
  }

  /// Exports metrics data for Admin Panel diagnostics display.
  Map<String, dynamic> getMetricsSummary() {
    final hits = _metrics['cache_hits'] as int;
    final misses = _metrics['cache_misses'] as int;
    final total = hits + misses;
    final ratio = total > 0 ? (hits / total) * 100 : 100.0;

    final latencies = _metrics['search_latency_ms'] as List<int>;
    final avgSearch = latencies.isNotEmpty 
        ? latencies.reduce((a, b) => a + b) / latencies.length 
        : 0.0;

    return {
      'startupTimeMs': _metrics['startup_ms'],
      'firestoreReads': _metrics['firestore_reads'],
      'firestoreWrites': _metrics['firestore_writes'],
      'cacheHitRatio': ratio.toStringAsFixed(1) + '%',
      'averageSearchLatencyMs': avgSearch.toStringAsFixed(0),
      'lastPlaybackStartupMs': _metrics['playback_start_ms'],
    };
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    _metrics.clear();
  }
}
