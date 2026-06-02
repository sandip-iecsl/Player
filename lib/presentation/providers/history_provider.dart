import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/song.dart';

const _searchHistoryBoxKey = 'searchHistory';
const _recentlyPlayedBoxKey = 'recentlyPlayed';

// ─── Search History ───────────────────────────────────────────────────────────

final searchHistoryProvider = StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
  return SearchHistoryNotifier();
});

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox<String>(_searchHistoryBoxKey);
    state = box.values.toList().reversed.take(20).toList();
  }

  Future<void> add(String query) async {
    if (query.trim().isEmpty) return;
    final box = await Hive.openBox<String>(_searchHistoryBoxKey);
    // Remove duplicate if exists
    final existing = box.values.toList();
    final dupIdx = existing.indexWhere((q) => q.toLowerCase() == query.toLowerCase());
    if (dupIdx != -1) {
      await box.deleteAt(dupIdx);
    }
    await box.add(query.trim());
    state = box.values.toList().reversed.take(20).toList();
  }

  Future<void> remove(String query) async {
    final box = await Hive.openBox<String>(_searchHistoryBoxKey);
    final idx = box.values.toList().indexWhere((q) => q == query);
    if (idx != -1) await box.deleteAt(idx);
    state = box.values.toList().reversed.take(20).toList();
  }

  Future<void> clear() async {
    final box = await Hive.openBox<String>(_searchHistoryBoxKey);
    await box.clear();
    state = [];
  }
}

// ─── Recently Played ─────────────────────────────────────────────────────────

final recentlyPlayedProvider = StateNotifierProvider<RecentlyPlayedNotifier, List<Song>>((ref) {
  return RecentlyPlayedNotifier();
});

class RecentlyPlayedNotifier extends StateNotifier<List<Song>> {
  RecentlyPlayedNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox<String>(_recentlyPlayedBoxKey);
    final songs = box.values
      .map((s) {
        try {
          return _songFromJson(jsonDecode(s));
        } catch (_) {
          return null;
        }
      })
      .whereType<Song>()
      .toList()
      .reversed
      .take(20)
      .toList();
    state = songs;
  }

  Future<void> add(Song song) async {
    final box = await Hive.openBox<String>(_recentlyPlayedBoxKey);
    final all = box.values.toList();
    // Remove duplicate by id
    final dupIdx = all.indexWhere((s) {
      try {
        return jsonDecode(s)['id'] == song.id;
      } catch (_) { return false; }
    });
    if (dupIdx != -1) await box.deleteAt(dupIdx);
    await box.add(jsonEncode(_songToJson(song)));
    state = box.values
      .map((s) {
        try { return _songFromJson(jsonDecode(s)); } catch (_) { return null; }
      })
      .whereType<Song>()
      .toList()
      .reversed
      .take(20)
      .toList();
  }

  Map<String, dynamic> _songToJson(Song s) => {
    'id': s.id,
    'title': s.title,
    'artist': s.artist,
    'album': s.album,
    'albumArt': s.albumArt,
    'duration': s.duration.inSeconds,
    'previewUrl': s.previewUrl,
    'youtubeUrl': s.youtubeUrl,
    'deezerUrl': s.deezerUrl,
  };

  Song _songFromJson(Map<String, dynamic> j) => Song(
    id: j['id'] ?? '',
    title: j['title'] ?? '',
    artist: j['artist'] ?? '',
    album: j['album'],
    albumArt: j['albumArt'],
    duration: Duration(seconds: j['duration'] ?? 0),
    previewUrl: j['previewUrl'],
    youtubeUrl: j['youtubeUrl'],
    deezerUrl: j['deezerUrl'],
  );
}
