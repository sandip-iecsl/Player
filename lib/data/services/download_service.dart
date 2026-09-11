import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/song.dart';
import '../models/song_model.dart';
import '../models/youtube_audio_format.dart';
import 'youtube_extractor_service.dart';

class DownloadService {
  final Dio _dio;

  DownloadService({required Dio dio}) : _dio = dio;

  /// Downloads a song with optional bitrate format selection and tags metadata
  Future<String?> downloadSong(
    Song song, {
    required Function(int, int) onProgress,
    YouTubeAudioFormat? selectedFormat,
    String? formatId,
    String? bitrate,
  }) async {
    if (kIsWeb) {
      debugPrint('[Download] Web download not supported');
      return null;
    }

    try {
      final isYoutube = song.isYoutubeImport || song.id.startsWith('yt_') || song.youtubeUrl != null;
      final targetFormatId = selectedFormat?.formatId ?? formatId ?? song.formatId;
      final targetBitrate = selectedFormat?.bitrate ?? bitrate ?? song.bitrate ?? '320 kbps';

      // 1. Resolve target download URL
      String? audioUrl = selectedFormat?.streamUrl ?? song.previewUrl;

      if (isYoutube) {
        if (selectedFormat != null && selectedFormat.streamUrl.isNotEmpty) {
          audioUrl = selectedFormat.streamUrl;
        } else if (audioUrl == null || audioUrl.isEmpty || audioUrl.startsWith('unstreamable')) {
          audioUrl = await YouTubeExtractorService().getFreshStreamUrl(song);
        }

        if (audioUrl == null || audioUrl.isEmpty) {
          audioUrl = YouTubeExtractorService().getDownloadUrl(
            song,
            formatId: targetFormatId,
            quality: selectedFormat?.quality,
          );
        }
      }

      if (audioUrl == null || audioUrl.isEmpty) {
        debugPrint('[Download] No audio URL for ${song.title}');
        return null;
      }

      debugPrint('[Download] 🚀 Starting download: "${song.title}" ($targetBitrate - Format ID: $targetFormatId)');
      final savedPath = await _downloadOnMobile(song, audioUrl, onProgress);

      if (savedPath != null) {
        // Register in offline_songs Hive box with bitrate and format metadata
        try {
          if (!Hive.isBoxOpen('offline_songs')) {
            await Hive.openBox('offline_songs');
          }
          final box = Hive.box('offline_songs');
          final songModel = SongModel(
            id: song.id,
            title: song.title,
            artist: song.artist,
            album: song.album ?? 'Offline Downloads',
            albumArt: song.albumArt,
            duration: song.duration,
            previewUrl: savedPath,
            youtubeUrl: song.youtubeUrl,
            isYoutubeImport: isYoutube,
            bitrate: targetBitrate,
            formatId: targetFormatId,
          );

          await box.put(song.id, {
            ...songModel.toJson(),
            'localPath': savedPath,
            'downloadedAt': DateTime.now().toIso8601String(),
            'bitrate': targetBitrate,
            'formatId': targetFormatId,
            'quality': selectedFormat?.quality ?? 'High',
            'isYoutubeImport': isYoutube,
            'youtubeUrl': song.youtubeUrl,
          });
          debugPrint('[Download] 💾 Offline indexed "${song.title}" with Bitrate: $targetBitrate');
        } catch (e) {
          debugPrint('[Download] Offline indexing note: $e');
        }
      }

      return savedPath;
    } catch (e) {
      debugPrint('[Download] Error: $e');
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
        debugPrint('[Download] Downloads directory not available');
        return null;
      }

      final auraDir = Directory('${directory.path}/AuraPlayer');
      if (!await auraDir.exists()) {
        await auraDir.create(recursive: true);
      }

      final isYoutube = song.isYoutubeImport || song.id.startsWith('yt_') || song.youtubeUrl != null;
      final selectedExtension = selectedFormat?.format.toLowerCase();
      final isWebm = selectedExtension == 'webm' || selectedExtension == 'opus' || targetFormatId == '249' || targetFormatId == '251';
      final ext = isYoutube
          ? (isWebm ? 'webm' : 'm4a')
          : 'mp3';
      final fileName = '${_sanitizeFileName(song.title)}.$ext';
      final filePath = '${auraDir.path}/$fileName';

      await _dio.download(
        audioUrl,
        filePath,
        onReceiveProgress: onProgress,
      );

      debugPrint('[Download] ✅ Saved binary file: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('[Download] Mobile download error: $e');
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
      final mp3Path = '${directory.path}/AuraPlayer/${_sanitizeFileName(song.title)}.mp3';
      final m4aPath = '${directory.path}/AuraPlayer/${_sanitizeFileName(song.title)}.m4a';
      return File(mp3Path).existsSync() || File(m4aPath).existsSync();
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
          .where((f) => f.path.endsWith('.mp3') || f.path.endsWith('.m4a'))
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
      final mp3Path = '${directory.path}/AuraPlayer/${_sanitizeFileName(song.title)}.mp3';
      final m4aPath = '${directory.path}/AuraPlayer/${_sanitizeFileName(song.title)}.m4a';
      for (final p in [mp3Path, m4aPath]) {
        final file = File(p);
        if (await file.exists()) {
          await file.delete();
          debugPrint('[Download] ✅ Deleted: ${song.title}');
        }
      }
    } catch (e) {
      debugPrint('[Download] Delete error: $e');
    }
  }
}
