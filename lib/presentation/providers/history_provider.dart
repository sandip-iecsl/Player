import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/song.dart';
import '../../data/services/cloud_sync_service.dart';
import '../../data/services/audio_service.dart';

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
    CloudSyncService().backupData();
  }

  Future<void> remove(String query) async {
    final box = await Hive.openBox<String>(_searchHistoryBoxKey);
    final idx = box.values.toList().indexWhere((q) => q == query);
    if (idx != -1) await box.deleteAt(idx);
    state = box.values.toList().reversed.take(20).toList();
    CloudSyncService().backupData();
  }

  Future<void> clear() async {
    final box = await Hive.openBox<String>(_searchHistoryBoxKey);
    await box.clear();
    state = [];
    CloudSyncService().backupData();
  }
}

// ─── Recently Played ─────────────────────────────────────────────────────────

final recentlyPlayedProvider = StateNotifierProvider<RecentlyPlayedNotifier, List<Song>>((ref) {
  return RecentlyPlayedNotifier();
});

class RecentlyPlayedNotifier extends StateNotifier<List<Song>> {
  StreamSubscription? _subscription;

  RecentlyPlayedNotifier() : super([]) {
    _load().then((_) => _listenToAudioHandler());
  }

  void _listenToAudioHandler() {
    _subscription = audioHandler.currentSongStream.listen((song) {
      if (song != null) {
        if (state.isEmpty || state.first.id != song.id) {
          add(song);
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
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
    final keysToDelete = <dynamic>[];
    for (int i = 0; i < box.length; i++) {
      try {
        final decoded = jsonDecode(box.getAt(i)!);
        if (decoded['id'] == song.id) {
          keysToDelete.add(box.keyAt(i));
          continue;
        }
        
        final existingTitle = (decoded['title'] as String).replaceAll(RegExp(r'[\(\[\-\|].*'), '').trim().toLowerCase();
        final newTitle = song.title.replaceAll(RegExp(r'[\(\[\-\|].*'), '').trim().toLowerCase();
        
        if (existingTitle.isNotEmpty && newTitle == existingTitle) {
          keysToDelete.add(box.keyAt(i));
        }
      } catch (_) {}
    }
    
    for (final key in keysToDelete) {
      await box.delete(key);
    }
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
    CloudSyncService().backupData();
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
