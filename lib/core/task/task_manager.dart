import 'dart:async';
import 'package:flutter/widgets.dart';
import '../kernel/i_engine.dart';
import '../shared/error/error_manager.dart';

enum TaskPriority { critical, high, medium, low, background }

class BackgroundTask {
  final String id;
  final TaskPriority priority;
  final FutureOr<void> Function() callback;
  final int maxRetries;
  int retryCount = 0;

  BackgroundTask({
    required this.id,
    required this.priority,
    required this.callback,
    this.maxRetries = 3,
  });
}

class TaskManager implements IEngine {
  static final TaskManager _instance = TaskManager._internal();
  factory TaskManager() => _instance;
  TaskManager._internal();

  final List<BackgroundTask> _taskQueue = [];
  bool _isProcessing = false;

  @override
  Future<void> initialize() async {
    debugPrint('[TaskManager] 📋 TaskManager initialized.');
  }

  @override
  Future<void> start() async {
    _processQueue();
  }

  /// Registers and submits a new background task for execution.
  void submitTask(BackgroundTask task) {
    _taskQueue.add(task);
    debugPrint('[TaskManager] 📋 Submitted task ${task.id} with priority: ${task.priority}');
    
    // Sort queue by priority: critical first, then high, medium, low, background
    _taskQueue.sort((a, b) => a.priority.index.compareTo(b.priority.index));

    if (task.priority == TaskPriority.critical) {
      _runTaskImmediately(task);
    } else {
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _taskQueue.isEmpty) return;
    _isProcessing = true;

    while (_taskQueue.isNotEmpty) {
      final task = _taskQueue.first;
      final success = await _runTaskSafely(task);
      
      if (success) {
        _taskQueue.removeAt(0);
      } else {
        task.retryCount++;
        if (task.retryCount >= task.maxRetries) {
          debugPrint('[TaskManager] ❌ Task ${task.id} failed after max retries.');
          _taskQueue.removeAt(0);
        } else {
          // Re-sort and pause execution loop for transient tasks
          _taskQueue.sort((a, b) => a.priority.index.compareTo(b.priority.index));
          break;
        }
      }
    }

    _isProcessing = false;
  }

  Future<void> _runTaskImmediately(BackgroundTask task) async {
    final success = await _runTaskSafely(task);
    if (success) {
      _taskQueue.remove(task);
    } else {
      task.retryCount++;
      if (task.retryCount >= task.maxRetries) {
        _taskQueue.remove(task);
      }
    }
  }

  Future<bool> _runTaskSafely(BackgroundTask task) async {
    try {
      await task.callback();
      return true;
    } catch (e, stack) {
      ErrorManager().captureError(e, stack, context: 'TaskManager.runTask.${task.id}');
      return false;
    }
  }

  @override
  Future<void> pause() async {
    _isProcessing = false;
  }

  @override
  Future<void> resume() async {
    _processQueue();
  }

  @override
  Future<void> stop() async {
    _isProcessing = false;
  }

  @override
  Future<void> dispose() async {
    _taskQueue.clear();
  }
}
