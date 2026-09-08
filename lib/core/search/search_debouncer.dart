import 'dart:async';
import 'package:flutter/foundation.dart';

/// 300ms Search Debouncer to eliminate wasteful keystroke calls and cloud reads
class SearchDebouncer {
  final Duration delay;
  Timer? _timer;

  SearchDebouncer({this.delay = const Duration(milliseconds: 300)});

  /// Debounces action execution
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Cancels any active timer
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Whether a debounce timer is currently ticking
  bool get isActive => _timer?.isActive ?? false;

  void dispose() {
    cancel();
  }
}
