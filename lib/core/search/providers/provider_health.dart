import 'package:flutter/foundation.dart';
import '../models/search_models.dart';

/// Circuit breaker state
enum CircuitBreakerState {
  closed,   // Normal operation, all traffic flows
  open,     // Failed threshold reached, traffic short-circuited
  halfOpen; // Testing provider recovery after cooldown

  String get label => name.toUpperCase();
}

/// Dynamic health tracker for an individual search provider
class ProviderHealth {
  final SearchProviderType provider;
  int timeoutCount;
  int failureCount;
  int httpErrorCount;
  int rateLimitCount;
  int consecutiveFailures;
  int totalRequests;
  int totalSuccesses;
  Duration totalLatency;
  DateTime? lastSuccess;
  DateTime? lastFailure;
  String? lastErrorMessage;
  CircuitBreakerState circuitState;
  DateTime? circuitOpenedAt;

  // Circuit breaker settings
  final int failureThreshold;
  final Duration cooldownDuration;

  ProviderHealth({
    required this.provider,
    this.timeoutCount = 0,
    this.failureCount = 0,
    this.httpErrorCount = 0,
    this.rateLimitCount = 0,
    this.consecutiveFailures = 0,
    this.totalRequests = 0,
    this.totalSuccesses = 0,
    this.totalLatency = Duration.zero,
    this.lastSuccess,
    this.lastFailure,
    this.lastErrorMessage,
    this.circuitState = CircuitBreakerState.closed,
    this.circuitOpenedAt,
    this.failureThreshold = 5,
    this.cooldownDuration = const Duration(seconds: 30),
  });

  Duration get averageLatency {
    if (totalSuccesses == 0) return Duration.zero;
    return Duration(microseconds: totalLatency.inMicroseconds ~/ totalSuccesses);
  }

  double get successRate {
    if (totalRequests == 0) return 1.0;
    return totalSuccesses / totalRequests;
  }

  bool get isAvailable {
    checkCircuitRecovery();
    return circuitState != CircuitBreakerState.open;
  }

  /// Checks if cooldown has passed to transition from OPEN -> HALF_OPEN
  void checkCircuitRecovery() {
    if (circuitState == CircuitBreakerState.open && circuitOpenedAt != null) {
      final elapsed = DateTime.now().difference(circuitOpenedAt!);
      if (elapsed >= cooldownDuration) {
        circuitState = CircuitBreakerState.halfOpen;
        debugPrint('[CircuitBreaker] 🔄 Provider ${provider.name} transitioned OPEN -> HALF_OPEN after cooldown');
      }
    }
  }

  /// Records a successful request
  void recordSuccess(Duration latency) {
    totalRequests++;
    totalSuccesses++;
    totalLatency += latency;
    lastSuccess = DateTime.now();
    consecutiveFailures = 0;
    lastErrorMessage = null;

    if (circuitState == CircuitBreakerState.halfOpen) {
      circuitState = CircuitBreakerState.closed;
      circuitOpenedAt = null;
      debugPrint('[CircuitBreaker] ✅ Provider ${provider.name} recovered: HALF_OPEN -> CLOSED');
    }
  }

  /// Records a failed request (error, timeout, 429)
  void recordFailure({
    required String error,
    bool isTimeout = false,
    bool isRateLimit = false,
    bool isHttpError = false,
  }) {
    totalRequests++;
    failureCount++;
    consecutiveFailures++;
    lastFailure = DateTime.now();
    lastErrorMessage = error;

    if (isTimeout) timeoutCount++;
    if (isRateLimit) rateLimitCount++;
    if (isHttpError) httpErrorCount++;

    if (consecutiveFailures >= failureThreshold || circuitState == CircuitBreakerState.halfOpen) {
      circuitState = CircuitBreakerState.open;
      circuitOpenedAt = DateTime.now();
      debugPrint('[CircuitBreaker] ⚠️ Provider ${provider.name} tripped: -> OPEN ($consecutiveFailures consecutive failures)');
    }
  }

  void reset() {
    timeoutCount = 0;
    failureCount = 0;
    httpErrorCount = 0;
    rateLimitCount = 0;
    consecutiveFailures = 0;
    totalRequests = 0;
    totalSuccesses = 0;
    totalLatency = Duration.zero;
    lastSuccess = null;
    lastFailure = null;
    lastErrorMessage = null;
    circuitState = CircuitBreakerState.closed;
    circuitOpenedAt = null;
  }

  Map<String, dynamic> toMap() {
    return {
      'provider': provider.name,
      'circuitState': circuitState.name,
      'successRate': '${(successRate * 100).toStringAsFixed(1)}%',
      'totalRequests': totalRequests,
      'totalSuccesses': totalSuccesses,
      'consecutiveFailures': consecutiveFailures,
      'timeoutCount': timeoutCount,
      'rateLimitCount': rateLimitCount,
      'httpErrorCount': httpErrorCount,
      'averageLatencyMs': averageLatency.inMilliseconds,
      'lastSuccess': lastSuccess?.toIso8601String(),
      'lastFailure': lastFailure?.toIso8601String(),
      'lastErrorMessage': lastErrorMessage,
    };
  }
}
