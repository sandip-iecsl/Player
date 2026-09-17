import 'package:flutter/foundation.dart';
import '../models/search_models.dart';

/// Telemetry logger for search operations
class SearchMetrics {
  static void logSearch(SearchResponse response) {
    debugPrint('════════════════════════════════════════════════════════════');
    debugPrint('🔎 [SearchTelemetry] Query: "${response.rawQuery}" | Normalized: "${response.parsedQuery.normalized}"');
    debugPrint('⏱️ Latency: ${response.totalLatency.inMilliseconds}ms | Cached: ${response.isFromCache} | Offline: ${response.isOfflineFallback}');
    debugPrint('🎯 Intent: ${response.parsedQuery.intent.name} | Lang: ${response.parsedQuery.detectedLanguage}');
    if (response.didYouMean != null) {
      debugPrint('💡 Did You Mean: "${response.didYouMean}"');
    }
    debugPrint('📊 Provider Breakdown:');
    response.providerLatencies.forEach((provider, latency) {
      final count = response.providerCandidateCounts[provider] ?? 0;
      final err = response.providerErrors[provider];
      debugPrint('   • ${provider.displayName}: $count items in ${latency.inMilliseconds}ms ${err != null ? "(Error: $err)" : "✅"}');
    });
    debugPrint('🏆 Top Results (${response.rankedResults.length}):');
    for (int i = 0; i < response.rankedResults.take(3).length; i++) {
      final r = response.rankedResults[i];
      debugPrint('   #${i + 1} [Score: ${(r.finalScore * 100).toStringAsFixed(1)}%] ${r.candidate.title} - ${r.candidate.artist} (${r.candidate.sourceProvider.name})');
    }
    debugPrint('════════════════════════════════════════════════════════════');
  }
}
