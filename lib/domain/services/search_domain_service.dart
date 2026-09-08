import '../../features/admin/engines/search_intelligence_engine.dart';
import '../../core/shared/metrics/metrics_engine.dart';

class SearchDomainService {
  static final SearchDomainService _instance = SearchDomainService._internal();
  factory SearchDomainService() => _instance;
  SearchDomainService._internal();

  /// Normalizes, enhances query, and tracks intelligence metrics.
  String prepareSearchQuery(String query) {
    final startTime = DateTime.now();
    final enhanced = SearchIntelligenceEngine().enhanceQuery(query);
    final duration = DateTime.now().difference(startTime).inMilliseconds;
    
    // Log search latency metrics
    MetricsEngine().recordSearchLatency(duration);
    return enhanced;
  }
}
