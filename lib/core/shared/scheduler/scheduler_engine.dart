import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../kernel/i_engine.dart';

class SchedulerEngine implements IEngine {
  static final SchedulerEngine _instance = SchedulerEngine._internal();
  factory SchedulerEngine() => _instance;
  SchedulerEngine._internal();

  Timer? _tickerTimer;
  final List<ScheduledTask> _tasks = [];
  bool _isRunning = false;

  @override
  Future<void> initialize() async {
    debugPrint('[SchedulerEngine] ⏰ Initialized.');
  }

  @override
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    // Tick once every second
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _onTick();
    });
    debugPrint('[SchedulerEngine] ⏰ Started ticker.');
  }

  /// Schedule a task to run periodically.
  void scheduleTask(String taskId, Duration interval, FutureOr<void> Function() callback) {
    // Remove if already exists
    _tasks.removeWhere((t) => t.id == taskId);
    _tasks.add(ScheduledTask(
      id: taskId,
      interval: interval,
      callback: callback,
      nextRun: DateTime.now().add(interval),
    ));
    debugPrint('[SchedulerEngine] ⏰ Scheduled task: $taskId (interval: ${interval.inSeconds}s)');
  }

  void unscheduleTask(String taskId) {
    _tasks.removeWhere((t) => t.id == taskId);
  }

  void _onTick() {
    final now = DateTime.now();
    for (final task in _tasks) {
      if (now.isAfter(task.nextRun)) {
        task.nextRun = now.add(task.interval);
        _runSafely(task);
      }
    }
  }

  Future<void> _runSafely(ScheduledTask task) async {
    try {
      await task.callback();
    } catch (e) {
      debugPrint('[SchedulerEngine] ⚠️ Error running scheduled task ${task.id}: $e');
    }
  }

  @override
  Future<void> pause() async {
    _tickerTimer?.cancel();
    _isRunning = false;
    debugPrint('[SchedulerEngine] ⏰ Paused.');
  }

  @override
  Future<void> resume() async {
    await start();
  }

  @override
  Future<void> stop() async {
    _tickerTimer?.cancel();
    _isRunning = false;
    debugPrint('[SchedulerEngine] ⏰ Stopped.');
  }

  @override
  Future<void> dispose() async {
    await stop();
    _tasks.clear();
  }
}

class ScheduledTask {
  final String id;
  final Duration interval;
  final FutureOr<void> Function() callback;
  DateTime nextRun;

  ScheduledTask({
    required this.id,
    required this.interval,
    required this.callback,
    required this.nextRun,
  });
}
