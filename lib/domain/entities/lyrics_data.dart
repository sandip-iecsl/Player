class LyricsLine {
  final Duration timestamp;
  final String text;

  LyricsLine({required this.timestamp, required this.text});
}

class LyricsData {
  final List<LyricsLine>? lines;
  final String? plainLyrics;

  LyricsData({this.lines, this.plainLyrics});

  bool get isSynced => lines != null && lines!.isNotEmpty;
  
  bool get isEmpty => (lines == null || lines!.isEmpty) && (plainLyrics == null || plainLyrics!.isEmpty);
}
