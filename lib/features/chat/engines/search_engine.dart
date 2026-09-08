import '../../../data/models/chat_message_model.dart';
import '../../admin/engines/search_intelligence_engine.dart';

class SearchEngine {
  static final SearchEngine _instance = SearchEngine._internal();
  factory SearchEngine() => _instance;
  SearchEngine._internal();

  /// Filters a list of messages based on a search query.
  /// If synonym expansion is enabled, it expands the query first.
  List<ChatMessageModel> searchMessages(List<ChatMessageModel> messages, String query, {bool useSynonyms = true}) {
    if (query.trim().isEmpty) return messages;

    final cleanQuery = query.toLowerCase().trim();
    final List<String> targetQueries = [cleanQuery];

    if (useSynonyms) {
      final enhanced = SearchIntelligenceEngine().enhanceQuery(cleanQuery);
      if (enhanced != cleanQuery) {
        targetQueries.add(enhanced);
      }
    }

    return messages.where((msg) {
      if (msg.deletedForEveryone) return false;
      final text = msg.text.toLowerCase();
      
      // Match if text contains any of the queries
      return targetQueries.any((q) => text.contains(q));
    }).toList();
  }
}
