import '../../domain/entities/song.dart';

class SongModel extends Song {
  SongModel({
    required super.id,
    required super.title,
    required super.artist,
    super.albumArt,
    super.album,
    required super.duration,
    super.youtubeUrl,
    super.deezerUrl,
    super.previewUrl,
  });

  factory SongModel.fromJson(Map<String, dynamic> json) {
    return SongModel(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Unknown',
      artist: json['artist'] ?? 'Unknown Artist',
      albumArt: json['albumArt'],
      album: json['album'],
      duration: Duration(seconds: json['duration'] ?? 0),
      youtubeUrl: json['youtubeUrl'],
      deezerUrl: json['deezerUrl'],
      previewUrl: json['previewUrl'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'albumArt': albumArt,
      'album': album,
      'duration': duration.inSeconds,
      'youtubeUrl': youtubeUrl,
      'deezerUrl': deezerUrl,
      'previewUrl': previewUrl,
    };
  }
}
