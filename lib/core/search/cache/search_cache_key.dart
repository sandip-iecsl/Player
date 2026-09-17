import '../models/search_models.dart';

/// Structured composite search cache key
class SearchCacheKey {
  final String normalizedQuery;
  final QueryIntent intent;
  final String language;
  final String region;

  const SearchCacheKey({
    required this.normalizedQuery,
    this.intent = QueryIntent.song,
    this.language = 'any',
    this.region = 'IN',
  });

  /// Formats key as: `normalized query|intent|language|region`
  String serialize() {
    return '$normalizedQuery|${intent.name}|$language|$region';
  }

  factory SearchCacheKey.fromParsedQuery(ParsedQuery query, {String region = 'IN'}) {
    return SearchCacheKey(
      normalizedQuery: query.normalized,
      intent: query.intent,
      language: query.detectedLanguage ?? 'any',
      region: region,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchCacheKey &&
          runtimeType == other.runtimeType &&
          normalizedQuery == other.normalizedQuery &&
          intent == other.intent &&
          language == other.language &&
          region == other.region;

  @override
  int get hashCode =>
      normalizedQuery.hashCode ^
      intent.hashCode ^
      language.hashCode ^
      region.hashCode;
}
