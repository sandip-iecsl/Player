import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/song.dart';

class DownloadService {
  final Dio _dio;

  DownloadService({required Dio dio}) : _dio = dio;

  Future<String?> downloadSong(
    Song song, {
    required Function(int, int) onProgress,
  }) async {
    if (kIsWeb) {
      print('[Download] Web download not supported');
      return null;
    }

    try {
      final audioUrl = song.previewUrl;
      if (audioUrl == null || audioUrl.isEmpty) {
        print('[Download] No audio URL for ${song.title}');
        return null;
      }

      print('[Download] Starting: ${song.title}');
      return await _downloadOnMobile(song, audioUrl, onProgress);
    } catch (e) {
      print('[Download] Error: $e');
      return null;
    }
  }

  Future<String?> _downloadOnMobile(
    Song song,
    String audioUrl,
    Function(int, int) onProgress,
  ) async {
    try {
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        print('[Download] Downloads directory not available');
        return null;
      }

      final auraDir = Directory('${directory.path}/AuraPlayer');
      if (!await auraDir.exists()) {
        await auraDir.create(recursive: true);
      }

      final fileName = '${_sanitizeFileName(song.title)}.mp3';
      final filePath = '${auraDir.path}/$fileName';

      await _dio.download(
        audioUrl,
        filePath,
        onReceiveProgress: onProgress,
      );

      print('[Download] ✅ Saved: $filePath');
      return filePath;
    } catch (e) {
      print('[Download] Mobile download error: $e');
      return null;
    }
  }

  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  Future<bool> isSongDownloaded(Song song) async {
    if (kIsWeb) return false;
    try {
      final directory = await getDownloadsDirectory();
      if (directory == null) return false;
      final filePath = '${directory.path}/AuraPlayer/${_sanitizeFileName(song.title)}.mp3';
      return File(filePath).existsSync();
    } catch (e) {
      return false;
    }
  }

  Future<List<File>> getDownloadedSongs() async {
    if (kIsWeb) return [];
    try {
      final directory = await getDownloadsDirectory();
      if (directory == null) return [];
      final auraDir = Directory('${directory.path}/AuraPlayer');
      if (!await auraDir.exists()) return [];
      return auraDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp3'))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteSongDownload(Song song) async {
    if (kIsWeb) return;
    try {
      final directory = await getDownloadsDirectory();
      if (directory == null) return;
      final filePath = '${directory.path}/AuraPlayer/${_sanitizeFileName(song.title)}.mp3';
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        print('[Download] ✅ Deleted: ${song.title}');
      }
    } catch (e) {
      print('[Download] Delete error: $e');
    }
  }
}
