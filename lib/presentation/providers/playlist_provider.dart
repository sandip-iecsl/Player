import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/song.dart';

const _playlistsBoxKey = 'userPlaylists';
const favoritesId = 'favorites_playlist_id';

class Playlist {
  final String id;
  final String name;
  final List<Song> songs;
  final String? coverUrl;

  Playlist({
    required this.id,
    required this.name,
    this.songs = const [],
    this.coverUrl,
  });

  Playlist copyWith({
    String? name,
    List<Song>? songs,
    String? coverUrl,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      songs: songs ?? this.songs,
      coverUrl: coverUrl ?? this.coverUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songs': songs.map((s) => _songToJson(s)).toList(),
    'coverUrl': coverUrl,
  };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
    id: j['id'] ?? '',
    name: j['name'] ?? '',
    songs: (j['songs'] as List? ?? [])
        .map((s) => _songFromJson(s as Map<String, dynamic>))
        .toList(),
    coverUrl: j['coverUrl'],
  );

  static Map<String, dynamic> _songToJson(Song s) => {
    'id': s.id,
    'title': s.title,
    'artist': s.artist,
    'album': s.album,
    'albumArt': s.albumArt,
    'duration': s.duration.inSeconds,
    'previewUrl': s.previewUrl,
  };

  static Song _songFromJson(Map<String, dynamic> j) => Song(
    id: j['id'] ?? '',
    title: j['title'] ?? '',
    artist: j['artist'] ?? '',
    album: j['album'],
    albumArt: j['albumArt'],
    duration: Duration(seconds: j['duration'] ?? 0),
    previewUrl: j['previewUrl'],
  );
}

final playlistProvider = StateNotifierProvider<PlaylistNotifier, List<Playlist>>((ref) {
  return PlaylistNotifier();
});

class PlaylistNotifier extends StateNotifier<List<Playlist>> {
  PlaylistNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox<String>(_playlistsBoxKey);
    final list = box.values.map((s) => Playlist.fromJson(jsonDecode(s))).toList();
    
    // Ensure Favorites exists
    if (!list.any((p) => p.id == favoritesId)) {
      final fav = Playlist(id: favoritesId, name: 'Favourite');
      await box.put(fav.id, jsonEncode(fav.toJson()));
      state = [fav, ...list];
    } else {
      // Move Favorites to top if it's not
      final fav = list.firstWhere((p) => p.id == favoritesId);
      final others = list.where((p) => p.id != favoritesId).toList();
      state = [fav, ...others];
    }
  }

  Future<String> createPlaylist(String name) async {
    final newPlaylist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    );
    final box = await Hive.openBox<String>(_playlistsBoxKey);
    await box.put(newPlaylist.id, jsonEncode(newPlaylist.toJson()));
    state = [...state, newPlaylist];
    return newPlaylist.id;
  }

  Future<void> deletePlaylist(String id) async {
    final box = await Hive.openBox<String>(_playlistsBoxKey);
    await box.delete(id);
    state = state.where((p) => p.id != id).toList();
  }

  Future<void> addSongToPlaylist(String playlistId, Song song) async {
    final playlistIdx = state.indexWhere((p) => p.id == playlistId);
    if (playlistIdx == -1) return;

    final playlist = state[playlistIdx];
    // Avoid duplicates
    if (playlist.songs.any((s) => s.id == song.id)) return;

    final updatedSongs = [...playlist.songs, song];
    final updatedPlaylist = playlist.copyWith(
      songs: updatedSongs,
      coverUrl: playlist.coverUrl ?? song.albumArt,
    );

    final box = await Hive.openBox<String>(_playlistsBoxKey);
    await box.put(playlistId, jsonEncode(updatedPlaylist.toJson()));

    final newState = [...state];
    newState[playlistIdx] = updatedPlaylist;
    state = newState;
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final playlistIdx = state.indexWhere((p) => p.id == playlistId);
    if (playlistIdx == -1) return;

    final playlist = state[playlistIdx];
    final updatedSongs = playlist.songs.where((s) => s.id != songId).toList();
    final updatedPlaylist = playlist.copyWith(songs: updatedSongs);

    final box = await Hive.openBox<String>(_playlistsBoxKey);
    await box.put(playlistId, jsonEncode(updatedPlaylist.toJson()));

    final newState = [...state];
    newState[playlistIdx] = updatedPlaylist;
    state = newState;
  }

  bool isFavorite(String songId) {
    final favPlaylist = state.firstWhere((p) => p.id == favoritesId, orElse: () => Playlist(id: favoritesId, name: 'Favourite'));
    return favPlaylist.songs.any((s) => s.id == songId);
  }

  Future<void> toggleFavorite(Song song) async {
    if (isFavorite(song.id)) {
      await removeSongFromPlaylist(favoritesId, song.id);
    } else {
      await addSongToPlaylist(favoritesId, song);
    }
  }
}
