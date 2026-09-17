import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/search_models.dart';
import '../providers/provider_health.dart';

/// Circuit breaker helper wrapping provider operations
class CircuitBreaker {
  /// Executes action through provider's health circuit breaker
  static Future<T?> execute<T>({
    required ProviderHealth health,
    required Future<T> Function() action,
    required Duration timeout,
    T? fallback,
  }) async {
    if (!health.isAvailable) {
      debugPrint('[CircuitBreaker] ⚠️ Provider ${health.provider.name} is ${health.circuitState.name.toUpperCase()} (Circuit Open). Skipping.');
      return fallback;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final result = await action().timeout(timeout);
      stopwatch.stop();
      health.recordSuccess(stopwatch.elapsed);
      return result;
    } on TimeoutException {
      stopwatch.stop();
      health.recordFailure(
        error: 'Timeout after ${timeout.inMilliseconds}ms',
        isTimeout: true,
      );
      return fallback;
    } catch (e) {
      stopwatch.stop();
      final is429 = e.toString().contains('429');
      health.recordFailure(
        error: e.toString(),
        isRateLimit: is429,
        isHttpError: !is429,
      );
      return fallback;
    }
  }
}
