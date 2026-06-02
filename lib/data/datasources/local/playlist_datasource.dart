import 'package:hive_flutter/hive_flutter.dart';
import '../../models/playlist_model.dart';
import '../../../domain/entities/song.dart';

class PlaylistDatasource {
  static const String _playlistBoxName = 'playlists';

  Future<void> createPlaylist(PlaylistModel playlist) async {
    final box = await Hive.openBox<Map>(_playlistBoxName);
    await box.put(playlist.id, playlist.toJson());
  }

  Future<List<PlaylistModel>> getAllPlaylists() async {
    final box = await Hive.openBox<Map>(_playlistBoxName);
    return box.values
        .map((data) => PlaylistModel.fromJson(Map<String, dynamic>.from(data)))
        .toList();
  }

  Future<PlaylistModel?> getPlaylist(String id) async {
    final box = await Hive.openBox<Map>(_playlistBoxName);
    final data = box.get(id);
    if (data == null) return null;
    return PlaylistModel.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> addSongToPlaylist(String playlistId, Song song) async {
    final box = await Hive.openBox<Map>(_playlistBoxName);
    final data = box.get(playlistId);
    if (data != null) {
      final playlist = PlaylistModel.fromJson(Map<String, dynamic>.from(data));
      playlist.songs.add(song);
      await box.put(playlistId, playlist.toJson());
    }
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final box = await Hive.openBox<Map>(_playlistBoxName);
    final data = box.get(playlistId);
    if (data != null) {
      final playlist = PlaylistModel.fromJson(Map<String, dynamic>.from(data));
      playlist.songs.removeWhere((song) => song.id == songId);
      await box.put(playlistId, playlist.toJson());
    }
  }

  Future<void> deletePlaylist(String id) async {
    final box = await Hive.openBox<Map>(_playlistBoxName);
    await box.delete(id);
  }

  Future<void> updatePlaylist(PlaylistModel playlist) async {
    final box = await Hive.openBox<Map>(_playlistBoxName);
    await box.put(playlist.id, playlist.toJson());
  }
}
