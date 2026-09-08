import 'package:flutter/widgets.dart';
import '../../kernel/i_engine.dart';
import '../../events/event_dispatcher.dart';
import '../../events/admin_events.dart';

class ErrorManager implements IEngine {
  static final ErrorManager _instance = ErrorManager._internal();
  factory ErrorManager() => _instance;
  ErrorManager._internal();

  final List<AppErrorInfo> _errorLog = [];

  @override
  Future<void> initialize() async {
    debugPrint('[ErrorManager] 🛠️ Initialized.');
  }

  @override
  Future<void> start() async {
    debugPrint('[ErrorManager] 🛠️ Listening for errors.');
  }

  /// Logs a caught exception and dispatches local alert events if severity warrants.
  void captureError(dynamic error, StackTrace? stack, {String? context, bool isFatal = false}) {
    final info = AppErrorInfo(
      error: error.toString(),
      context: context ?? 'unknown',
      timestamp: DateTime.now(),
      isFatal: isFatal,
    );

    _errorLog.add(info);
    debugPrint('[ErrorManager] ⚠️ Captured error: ${info.error} in context: ${info.context}');

    // Dispatch queue failed or generic error event via Event Bus
    EventDispatcher().publish(QueueFailedEvent(
      eventId: 'err_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      error: '[${info.context}] ${info.error}',
    ));
  }

  List<AppErrorInfo> getLogs() => List.unmodifiable(_errorLog);

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    _errorLog.clear();
  }
}

class AppErrorInfo {
  final String error;
  final String context;
  final DateTime timestamp;
  final bool isFatal;

  AppErrorInfo({
    required this.error,
    required this.context,
    required this.timestamp,
    required this.isFatal,
  });
}
