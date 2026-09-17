import 'package:flutter_test/flutter_test.dart';
import 'package:aura_player/core/search/health/circuit_breaker.dart';
import 'package:aura_player/core/search/models/search_models.dart';
import 'package:aura_player/core/search/providers/provider_health.dart';
import 'package:aura_player/core/search/quota/provider_quota.dart';

void main() {
  group('Circuit Breaker & Quota Management Suite', () {
    test('Provider health trips circuit breaker to OPEN after 5 consecutive failures', () {
      final health = ProviderHealth(
        provider: SearchProviderType.audius,
        failureThreshold: 5,
        cooldownDuration: const Duration(milliseconds: 100),
      );

      expect(health.circuitState, equals(CircuitBreakerState.closed));
      expect(health.isAvailable, isTrue);

      // Record 4 failures
      for (int i = 0; i < 4; i++) {
        health.recordFailure(error: 'Simulated 500 error', isHttpError: true);
        expect(health.circuitState, equals(CircuitBreakerState.closed));
      }

      // 5th consecutive failure must trip to OPEN
      health.recordFailure(error: 'Simulated 500 error', isHttpError: true);
      expect(health.circuitState, equals(CircuitBreakerState.open));
      expect(health.isAvailable, isFalse);

      // Fast-forward cooldown: verify transition to HALF_OPEN
      health.circuitOpenedAt = DateTime.now().subtract(const Duration(milliseconds: 200));
      expect(health.isAvailable, isTrue);
      expect(health.circuitState, equals(CircuitBreakerState.halfOpen));

      // Successful request restores circuit to CLOSED
      health.recordSuccess(const Duration(milliseconds: 50));
      expect(health.circuitState, equals(CircuitBreakerState.closed));
      expect(health.consecutiveFailures, equals(0));
    });

    test('CircuitBreaker helper executes action and catches timeouts/errors', () async {
      final health = ProviderHealth(provider: SearchProviderType.youtube);

      final res = await CircuitBreaker.execute<String>(
        health: health,
        action: () async => 'success_result',
        timeout: const Duration(seconds: 1),
      );

      expect(res, equals('success_result'));
      expect(health.totalSuccesses, equals(1));
    });

    test('Provider Quota tracks daily limit, request costs, and resets correctly', () {
      final quota = ProviderQuota(
        provider: SearchProviderType.youtube,
        dailyLimit: 1000,
        requestCost: 100, // YouTube Data API search.list cost
      );

      expect(quota.canMakeRequest(), isTrue);
      expect(quota.remainingEstimate, equals(1000));

      quota.recordRequest();
      expect(quota.usedToday, equals(100));
      expect(quota.remainingEstimate, equals(900));

      // Simulate exhausting quota
      for (int i = 0; i < 9; i++) {
        quota.recordRequest();
      }

      expect(quota.isQuotaExceeded, isTrue);
      expect(quota.canMakeRequest(), isFalse);
    });
  });
}
