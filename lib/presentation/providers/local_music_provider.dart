import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';

const _channel = MethodChannel('com.example.free_play/permissions');

Future<bool> _osHasPermission() async {
  try {
    return await _channel.invokeMethod<bool>('checkStoragePermission') ?? false;
  } catch (_) {
    return false;
  }
}

Future<bool> _osRequestPermission() async {
  try {
    return await _channel.invokeMethod<bool>('requestStoragePermission') ?? false;
  } catch (_) {
    return false;
  }
}

// ── Permission notifier ─────────────────────────────────────────────────────
class LocalPermissionNotifier extends StateNotifier<bool> {
  bool _requesting = false;

  LocalPermissionNotifier() : super(false) {
    Future.microtask(_init);
  }

  Future<void> _init() async {
    if (!mounted) return;
    final granted = await _osHasPermission();
    print('[LocalMusic] Permission check result: $granted');
    if (mounted) state = granted;
  }

  Future<void> requestOnce() async {
    if (state || _requesting) return;
    _requesting = true;
    try {
      final granted = await _osRequestPermission();
      if (mounted) state = granted;
    } catch (_) {}
    _requesting = false;
  }
}

final localPermissionProvider =
    StateNotifierProvider<LocalPermissionNotifier, bool>(
        (_) => LocalPermissionNotifier());

// ── Scan music files directly via dart:io ───────────────────────────────────
// No on_audio_query permission system involved at all

const _audioExtensions = {'.mp3', '.mp4', '.m4a', '.flac', '.wav', '.aac', '.ogg', '.opus', '.wma'};

// Directories to skip entirely during recursive scan (system/cache folders)
const _skipDirs = {
  'Android',
  '.thumbnails',
  '.cache',
  'cache',
  'Cache',
  'data',
  'obb',
  'proc',
  'sys',
  'dev',
  'acct',
  'etc',
};

Future<List<Song>> _scanAllSongs() async {
  final songs = <Song>[];
  final seen = <String>{};

  // Build list of storage roots to scan
  final roots = <String>['/storage/emulated/0'];

  // Also check for external SD cards under /storage/
  try {
    final storageDir = Directory('/storage');
    await for (final entity in storageDir.list(followLinks: false)) {
      if (entity is Directory) {
        final name = entity.path.split('/').last;
        if (name != 'emulated' && name != 'self') {
          roots.add(entity.path);
        }
      }
    }
  } catch (_) {}

  for (final root in roots) {
    final dir = Directory(root);
    if (!await dir.exists()) continue;
    print('[LocalScan] Scanning root: $root');
    await _scanDir(dir, songs, seen);
  }

  print('[LocalScan] Total songs found: ${songs.length}');
  songs.sort((a, b) => a.title.compareTo(b.title));
  return songs;
}

Future<void> _scanDir(Directory dir, List<Song> songs, Set<String> seen) async {
  try {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        final name = entity.path.split('/').last;
        if (!name.startsWith('.') && !_skipDirs.contains(name)) {
          await _scanDir(entity, songs, seen);
        }
      } else if (entity is File) {
        final path = entity.path;
        if (seen.contains(path)) continue;
        final lower = path.toLowerCase();
        if (_audioExtensions.any((e) => lower.endsWith(e))) {
          seen.add(path);
          print('[LocalScan] Found: $path');
          songs.add(_fileToSong(entity));
        }
      }
    }
  } catch (e) {
    print('[LocalScan] Error scanning ${dir.path}: $e');
  }
}

Song _fileToSong(File f) {
  final name = f.uri.pathSegments.last;
  // Strip extension for title
  final title = name.contains('.')
      ? name.substring(0, name.lastIndexOf('.'))
      : name;
  return Song(
    id: f.path.hashCode.toString(),
    title: title,
    artist: 'Unknown Artist',
    albumArt: null,
    duration: Duration.zero,
    previewUrl: f.path,
  );
}

// Group songs by parent folder as "albums"
class LocalFolder {
  final String name;
  final String path;
  final List<Song> songs;
  LocalFolder({required this.name, required this.path, required this.songs});
}

// ── Providers ───────────────────────────────────────────────────────────────

final allLocalSongsProvider = FutureProvider<List<Song>>((ref) async {
  if (!ref.watch(localPermissionProvider)) return [];
  return _scanAllSongs();
});

final localFoldersProvider = FutureProvider<List<LocalFolder>>((ref) async {
  if (!ref.watch(localPermissionProvider)) return [];
  final songs = await ref.watch(allLocalSongsProvider.future);
  if (songs.isEmpty) return [];

  // Group by parent directory
  final map = <String, List<Song>>{};
  for (final song in songs) {
    if (song.previewUrl == null) continue;
    final parent = File(song.previewUrl!).parent.path;
    map.putIfAbsent(parent, () => []).add(song);
  }

  return map.entries
      .map((e) => LocalFolder(
            name: e.key.split('/').last,
            path: e.key,
            songs: e.value,
          ))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

final localFolderSongsProvider =
    FutureProvider.family<List<Song>, String>((ref, folderPath) async {
  final all = await ref.watch(allLocalSongsProvider.future);
  return all
      .where((s) =>
          s.previewUrl != null &&
          File(s.previewUrl!).parent.path == folderPath)
      .toList();
});
