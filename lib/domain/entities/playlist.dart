import 'song.dart';

class Playlist {
  final String id;
  final String name;
  final String? description;
  final List<Song> songs;
  final DateTime createdAt;
  final String? coverImage;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    required this.songs,
    required this.createdAt,
    this.coverImage,
  });

  int get duration {
    return songs.fold(0, (sum, song) => sum + song.duration.inSeconds);
  }
}
