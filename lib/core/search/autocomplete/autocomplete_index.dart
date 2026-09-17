/// Trie Node for high performance in-memory prefix autocomplete
class _TrieNode {
  final Map<String, _TrieNode> children = {};
  final Set<String> suggestions = {};
  bool isEndOfWord = false;
}

/// In-memory Prefix Search Index for near-instant (<50ms) local autocomplete
class AutocompleteIndex {
  final _TrieNode _root = _TrieNode();
  final Set<String> _allEntries = {};

  void insert(String phrase) {
    final clean = phrase.toLowerCase().trim();
    if (clean.isEmpty || _allEntries.contains(clean)) return;

    _allEntries.add(clean);
    _TrieNode current = _root;

    for (int i = 0; i < clean.length; i++) {
      final char = clean[i];
      current = current.children.putIfAbsent(char, () => _TrieNode());
      if (current.suggestions.length < 15) {
        current.suggestions.add(clean);
      }
    }
    current.isEndOfWord = true;
  }

  void insertAll(Iterable<String> phrases) {
    for (final p in phrases) {
      insert(p);
    }
  }

  List<String> lookupPrefix(String prefix, {int limit = 8}) {
    final clean = prefix.toLowerCase().trim();
    if (clean.isEmpty) return [];

    _TrieNode current = _root;
    for (int i = 0; i < clean.length; i++) {
      final char = clean[i];
      if (!current.children.containsKey(char)) {
        return [];
      }
      current = current.children[char]!;
    }

    return current.suggestions.take(limit).toList();
  }

  Set<String> get allEntries => _allEntries;
}
