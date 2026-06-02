class Song {
  final String id;
  final String title;
  final String artist;
  final String? albumArt;
  final String? album;
  final Duration duration;
  final String? youtubeUrl;
  final String? deezerUrl;
  final String? previewUrl; // Direct 30s MP3 stream from Deezer

  Song({
    required this.id,
    required this.title,
    required this.artist,
    this.albumArt,
    this.album,
    required this.duration,
    this.youtubeUrl,
    this.deezerUrl,
    this.previewUrl,
  });
}
