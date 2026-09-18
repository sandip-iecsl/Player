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
      final isYoutube = song.isYoutubeImport ||
          song.id.startsWith('yt_') ||
          song.youtubeUrl != null;
      final targetFormatId =
          selectedFormat?.formatId ?? formatId ?? song.formatId;
      final targetBitrate =
          selectedFormat?.bitrate ?? bitrate ?? song.bitrate ?? '320 kbps';

      // 1. Resolve target download URL
      String? audioUrl = selectedFormat?.streamUrl ?? song.previewUrl;

      if (isYoutube) {
        if (selectedFormat != null && selectedFormat.streamUrl.isNotEmpty) {
          audioUrl = selectedFormat.streamUrl;
        } else if (audioUrl == null ||
            audioUrl.isEmpty ||
            audioUrl.startsWith('unstreamable')) {
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

      debugPrint(
          '[Download] 🚀 Starting download: "${song.title}" ($targetBitrate - Format ID: $targetFormatId)');
      final savedPath = await _downloadOnMobile(
        song,
        audioUrl,
        onProgress,
        selectedFormat: selectedFormat,
        targetFormatId: targetFormatId,
      );

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
          debugPrint(
              '[Download] 💾 Offline indexed "${song.title}" with Bitrate: $targetBitrate');
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
    Function(int, int) onProgress, {
    YouTubeAudioFormat? selectedFormat,
    String? targetFormatId,
  }) async {
    String? temporaryPath;
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

      final isYoutube = song.isYoutubeImport ||
          song.id.startsWith('yt_') ||
          song.youtubeUrl != null;
      final selectedExtension = selectedFormat?.format.toLowerCase();
      final isOpus = selectedExtension == 'opus' ||
          targetFormatId == '251' ||
          targetFormatId == '250';
      final isWebm = selectedExtension == 'webm' || targetFormatId == '249';
      final ext = isYoutube
          ? (isOpus
              ? 'opus'
              : isWebm
                  ? 'webm'
                  : 'm4a')
          : (selectedExtension ?? 'mp3');
      final fileName = '${_sanitizeFileName(song.title)}.$ext';
      final filePath = '${auraDir.path}/$fileName';
      temporaryPath = '$filePath.part';
      final temporaryFile = File(temporaryPath);

      if (await temporaryFile.exists()) await temporaryFile.delete();
      final response = await _dio.get<ResponseBody>(
        audioUrl,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 3),
          sendTimeout: const Duration(seconds: 30),
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );

      final contentType =
          response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ??
              '';
      if (contentType.contains('text/html') ||
          contentType.contains('application/json')) {
        throw StateError('download response is not audio: $contentType');
      }

      final total = response.headers.value(Headers.contentLengthHeader);
      final totalBytes = int.tryParse(total ?? '') ?? -1;
      var received = 0;
      final sink = temporaryFile.openWrite();
      try {
        await for (final chunk in response.data!.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, totalBytes);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (received < 16 * 1024 || !await _hasAudioSignature(temporaryFile)) {
        throw StateError('downloaded file failed audio validation');
      }

      final finalFile = File(filePath);
      if (await finalFile.exists()) await finalFile.delete();
      final committedFile = await temporaryFile.rename(filePath);
      debugPrint(
          '[Download] ✅ Validated and saved binary file: ${committedFile.path}');
      return committedFile.path;
    } catch (e) {
      debugPrint('[Download] Mobile download error: $e');
      try {
        final directory = await getDownloadsDirectory();
        if (temporaryPath != null && directory != null) {
          final partial = File(temporaryPath);
          if (await partial.exists()) await partial.delete();
        }
      } catch (_) {}
      return null;
    }
  }

  Future<bool> _hasAudioSignature(File file) async {
    final bytes = await file
        .openRead(0, 16)
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
    if (bytes.length < 4) return false;
    final isOgg = bytes[0] == 0x4f &&
        bytes[1] == 0x67 &&
        bytes[2] == 0x67 &&
        bytes[3] == 0x53;
    final isWebm = bytes.length >= 4 &&
        bytes[0] == 0x1a &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xdf &&
        bytes[3] == 0xa3;
    final isMp4 = bytes.length >= 8 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70;
    final isId3 = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
    return isOgg || isWebm || isMp4 || isId3;
  }

  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  Future<bool> isSongDownloaded(Song song) async {
    if (kIsWeb) return false;
    try {
      final directory = await getDownloadsDirectory();
      if (directory == null) return false;
      final base =
          '${directory.path}/AuraPlayer/${_sanitizeFileName(song.title)}';
      for (final ext in ['m4a', 'opus', 'webm', 'mp3']) {
        if (File('$base.$ext').existsSync()) return true;
      }
      return false;
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
          .where((f) =>
              f.path.endsWith('.mp3') ||
              f.path.endsWith('.m4a') ||
              f.path.endsWith('.opus') ||
              f.path.endsWith('.webm'))
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
      final base =
          '${directory.path}/AuraPlayer/${_sanitizeFileName(song.title)}';
      for (final ext in ['m4a', 'opus', 'webm', 'mp3']) {
        final file = File('$base.$ext');
        if (await file.exists()) {
          await file.delete();
          debugPrint('[Download] ✅ Deleted: ${song.title}.$ext');
        }
      }
    } catch (e) {
      debugPrint('[Download] Delete error: $e');
    }
  }
}
