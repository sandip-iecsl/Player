import 'package:flutter/foundation.dart';

/// The tier levels of the search infrastructure
enum SearchTier {
  /// Tier 0: 0ms latency, zero cloud cost instant cache
  cache(0, 'Local Hive Cache', '0ms (Instant Cache)'),

  /// Tier 1: Primary Cloud Engine (MongoDB Atlas Search / Lucene)
  tier1MongoAtlas(1, 'MongoDB Atlas Search', 'Tier 1 (Primary Cloud)'),

  /// Tier 2: Secondary Cloud Backup (Algolia Search Free Tier)
  tier2Algolia(2, 'Algolia Search', 'Tier 2 (Secondary Cloud)'),

  /// Tier 3: 100% Offline Client-Side Fuzzy / SQLite Engine (0 Cloud Reads)
  tier3LocalFailsafe(3, 'Local Fuzzy Engine', 'Tier 3 (Local Fail-Safe)');

  final int level;
  final String displayName;
  final String label;

  const SearchTier(this.level, this.displayName, this.label);

  bool get isLocal => this == SearchTier.cache || this == SearchTier.tier3LocalFailsafe;
  bool get isCloud => this == SearchTier.tier1MongoAtlas || this == SearchTier.tier2Algolia;
  bool get isOfflineFailsafe => this == SearchTier.tier3LocalFailsafe;
}

/// Diagnostic metric event emitted when a search tier fails or succeeds
@immutable
class SearchMetricEvent {
  final String providerName;
  final SearchTier tier;
  final String query;
  final bool isSuccess;
  final Duration duration;
  final String? errorMessage;
  final int? statusCode;
  final int resultCount;
  final DateTime timestamp;

  SearchMetricEvent({
    required this.providerName,
    required this.tier,
    required this.query,
    required this.isSuccess,
    required this.duration,
    this.errorMessage,
    this.statusCode,
    this.resultCount = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return '[SearchMetric] Provider: $providerName ($tier) | Query: "$query" | Success: $isSuccess | Duration: ${duration.inMilliseconds}ms | Results: $resultCount${errorMessage != null ? " | Error: $errorMessage (Code: $statusCode)" : ""}';
  }
}
