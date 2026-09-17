import '../models/search_models.dart';
import 'provider_health.dart';

/// Provider-independent contract that all search providers must implement.
/// Ensures all providers return the unified SearchCandidate representation.
abstract interface class SearchProviderClient {
  /// The specific provider type
  SearchProviderType get provider;

  /// Health tracker and circuit breaker state
  ProviderHealth get health;

  /// Whether this provider is enabled by default or configuration
  bool get isEnabled;

  /// Priority of this provider in candidate retrieval
  int get priority;

  /// Default timeout for this provider
  Duration get timeout;

  /// Performs search and returns canonical SearchCandidate items
  Future<List<SearchCandidate>> search(
    ParsedQuery query,
    SearchRequest request,
  );
}
