import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Circuit Breaker Interceptor for Dio.
/// Monitors for consecutive 429 (Rate Limit) and 5xx (Server Error) responses.
/// Trips after 3 consecutive failures, opening the circuit for 5 minutes.
/// When open, it immediately rejects requests with a cancelled DioException to fast-fail.
class CircuitBreakerInterceptor extends Interceptor {
  int _failureCount = 0;
  bool _isOpen = false;
  DateTime? _openTime;

  static const int _maxFailures = 3;
  static const Duration _cooldownDuration = Duration(minutes: 5);

  bool get isOpen {
    if (_isOpen && _openTime != null) {
      if (DateTime.now().difference(_openTime!) >= _cooldownDuration) {
        // Cooldown period elapsed, transition to half-open (allow testing)
        debugPrint('[CircuitBreaker] 🟡 Cooldown elapsed. Circuit transitions to Half-Open.');
        _isOpen = false;
        return false;
      }
      return true;
    }
    return false;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (isOpen) {
      debugPrint('[CircuitBreaker] 🛑 Circuit is OPEN. Fast-failing request to: ${options.path}');
      // Fast-fail: Reject the request immediately with a custom DioException
      final exception = DioException(
        requestOptions: options,
        error: 'Circuit breaker is open. JioSaavn API is cooling down.',
        type: DioExceptionType.cancel,
        message: 'Circuit breaker is open. Fast-failing to trigger immediate fallback.',
      );
      return handler.reject(exception);
    }
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // A successful response resets the failure counter
    if (_failureCount > 0) {
      debugPrint('[CircuitBreaker] 🟢 Successful response. Resetting failure count (was $_failureCount).');
      _failureCount = 0;
    }
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final statusCode = err.response?.statusCode;
    
    // Check if error qualifies as a circuit-breaking failure:
    // - HTTP status code 429 (Too Many Requests)
    // - HTTP status code 5xx (Server Error)
    // - Connection timeout, send timeout, receive timeout, or connection error
    final isRateLimit = statusCode == 429;
    final isServerError = statusCode != null && statusCode >= 500;
    final isTimeoutOrNetworkError = 
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError;

    if (isRateLimit || isServerError || isTimeoutOrNetworkError) {
      _failureCount++;
      debugPrint('[CircuitBreaker] ⚠️ Failure detected ($statusCode / ${err.type}). Count: $_failureCount/$_maxFailures');
      
      if (_failureCount >= _maxFailures && !_isOpen) {
        _isOpen = true;
        _openTime = DateTime.now();
        debugPrint('[CircuitBreaker] 🚨 Breaker TRIPPED! Opening circuit for ${_cooldownDuration.inMinutes} minutes at $_openTime.');
      }
    } else {
      // Other errors do not count towards the circuit breaker
      debugPrint('[CircuitBreaker] ℹ️ Error ignored for circuit breaker: $statusCode / ${err.type}');
    }

    super.onError(err, handler);
  }

  /// Manually trip the circuit breaker for testing/verification.
  void forceTrip() {
    _failureCount = _maxFailures;
    _isOpen = true;
    _openTime = DateTime.now();
    debugPrint('[CircuitBreaker] 🚨 Circuit breaker manually TRIPPED for testing.');
  }

  /// Manually reset the circuit breaker.
  void reset() {
    _failureCount = 0;
    _isOpen = false;
    _openTime = null;
    debugPrint('[CircuitBreaker] 🟢 Circuit breaker manually RESET.');
  }
}
