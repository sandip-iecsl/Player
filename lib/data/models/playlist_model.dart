import '../../domain/entities/playlist.dart';
import 'song_model.dart';

class PlaylistModel extends Playlist {
  PlaylistModel({
    required super.id,
    required super.name,
    super.description,
    required super.songs,
    required super.createdAt,
    super.coverImage,
  });

  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    return PlaylistModel(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Untitled Playlist',
      description: json['description'],
      songs: (json['songs'] as List?)
              ?.map((song) => SongModel.fromJson(song))
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      coverImage: json['coverImage'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'songs': songs.map((song) => (song as SongModel).toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'coverImage': coverImage,
    };
  }
}
