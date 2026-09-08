import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song_model.dart';
import '../../domain/entities/song.dart';
import 'youtube_extractor_service.dart';

class OfflineStorageService {
  static const int maxSongs = 50;
  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  ));

  /// Check if a song is downloaded
  static bool isDownloaded(String songId) {
    if (songId.isEmpty) return false;
    if (!Hive.isBoxOpen('offline_songs')) return false;
    return getLocalPath(songId) != null;
  }

  /// Get local path for a downloaded song, or null if not downloaded
  static String? getLocalPath(String songId) {
    if (songId.isEmpty) return null;
    if (!Hive.isBoxOpen('offline_songs')) return null;
    final box = Hive.box('offline_songs');
    
    Map? data = box.get(songId) as Map?;
    if (data == null && songId.startsWith('yt_')) {
      data = box.get(songId.replaceFirst('yt_', '')) as Map?;
    } else if (data == null && !songId.startsWith('yt_')) {
      data = box.get('yt_$songId') as Map?;
    }

    if (data != null && data['localPath'] != null) {
      final file = File(data['localPath']);
      if (file.existsSync()) {
        return file.path;
      } else {
        // Check if matching .m4a or .mp3 exists in directory
        final appDir = file.parent;
        final m4a = File('${appDir.path}/offline_$songId.m4a');
        final mp3 = File('${appDir.path}/offline_$songId.mp3');
        if (m4a.existsSync()) return m4a.path;
        if (mp3.existsSync()) return mp3.path;

        // File is missing but DB has it, cleanup DB
        box.delete(songId);
      }
    }
    return null;
  }

  /// Download a song (including YouTube links, JioSaavn, Spotify, Deezer)
  static Future<bool> downloadSong(
    Song song,
    void Function(double) onProgress, {
    dynamic selectedFormat,
    String? formatId,
    String? bitrate,
  }) async {
    if (!Hive.isBoxOpen('offline_songs')) {
      await Hive.openBox('offline_songs');
    }
    final box = Hive.box('offline_songs');
    
    if (box.length >= maxSongs && !box.containsKey(song.id)) {
      throw Exception('Offline limit reached. Please remove a song first.');
    }

    final isYoutube = song.isYoutubeImport || song.id.startsWith('yt_') || song.youtubeUrl != null;
    final targetFormatId = formatId ?? (selectedFormat != null ? selectedFormat.formatId as String? : null) ?? song.formatId;
    final targetBitrate = bitrate ?? (selectedFormat != null ? selectedFormat.bitrate as String? : null) ?? song.bitrate ?? '320 kbps';
    final targetQuality = selectedFormat != null ? selectedFormat.quality as String : 'High';

    String? audioUrl = (selectedFormat != null && selectedFormat.streamUrl != null && selectedFormat.streamUrl.toString().isNotEmpty)
        ? selectedFormat.streamUrl.toString()
        : song.previewUrl;

    // Dynamically refresh or extract stream URL if missing or unstreamable
    if ((audioUrl == null || audioUrl.isEmpty || audioUrl.startsWith('unstreamable')) && song.id.isNotEmpty) {
      if (isYoutube) {
        debugPrint('[Offline] 🎬 Resolving fresh YouTube stream URL for "${song.title}"...');
        audioUrl = await YouTubeExtractorService().getFreshStreamUrl(song);
      }
    }

    // Secondary fallback for YouTube: Use Microservice Download Endpoint
    final downloadEndpointUrl = isYoutube
        ? YouTubeExtractorService().getDownloadUrl(
            song,
            formatId: targetFormatId,
            quality: targetQuality,
          )
        : null;
    final primaryDownloadUrl = audioUrl ?? downloadEndpointUrl;

    if (primaryDownloadUrl == null || primaryDownloadUrl.isEmpty) {
      throw Exception('No audio URL available for download.');
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = isYoutube ? 'm4a' : 'mp3';
      final audioPath = '${dir.path}/offline_${song.id}.$ext';
      
      debugPrint('[Offline] ⬇️ Downloading "${song.title}" ($targetBitrate) to $audioPath from $primaryDownloadUrl');

      // Download audio with fallback to microservice endpoint if primary fails
      try {
        await _dio.download(
          primaryDownloadUrl,
          audioPath,
          onReceiveProgress: (count, total) {
            if (total != -1 && total > 0) {
              onProgress(count / total);
            }
          },
        );
      } catch (directDownloadErr) {
        if (isYoutube && downloadEndpointUrl != null && primaryDownloadUrl != downloadEndpointUrl) {
          debugPrint('[Offline] ⚠️ Direct download failed ($directDownloadErr). Trying microservice proxy: $downloadEndpointUrl');
          await _dio.download(
            downloadEndpointUrl,
            audioPath,
            onReceiveProgress: (count, total) {
              if (total != -1 && total > 0) {
                onProgress(count / total);
              }
            },
          );
        } else {
          rethrow;
        }
      }

      // Download album art if available
      String? localArtPath;
      if (song.albumArt != null && song.albumArt!.startsWith('http')) {
        final artPath = '${dir.path}/offline_art_${song.id}.jpg';
        try {
          await _dio.download(song.albumArt!, artPath);
          localArtPath = artPath;
        } catch (e) {
          debugPrint('[Offline] Failed to download album art: $e');
        }
      }

      // Save to Hive offline_songs box
      final songModel = SongModel(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album ?? 'Offline Downloads',
        albumArt: localArtPath ?? song.albumArt,
        duration: song.duration,
        previewUrl: audioPath, // Local file path for instant offline playback
        youtubeUrl: song.youtubeUrl,
        isYoutubeImport: isYoutube,
        bitrate: targetBitrate,
        formatId: targetFormatId,
      );

      await box.put(song.id, {
        ...songModel.toJson(),
        'localPath': audioPath,
        'downloadedAt': DateTime.now().toIso8601String(),
        'bitrate': targetBitrate,
        'formatId': targetFormatId,
        'quality': targetQuality,
        'isYoutubeImport': isYoutube,
        'youtubeUrl': song.youtubeUrl,
      });

      debugPrint('[Offline] ✅ Successfully downloaded and indexed "${song.title}" with Bitrate: $targetBitrate');
      return true;
    } catch (e) {
      debugPrint('[Offline] ❌ Failed to download song: $e');
      rethrow;
    }
  }

  /// Remove a downloaded song
  static Future<void> removeSong(String songId) async {
    if (!Hive.isBoxOpen('offline_songs')) return;
    final box = Hive.box('offline_songs');
    final data = box.get(songId) as Map?;
    if (data != null) {
      final audioPath = data['localPath'];
      if (audioPath != null) {
        final file = File(audioPath);
        if (file.existsSync()) file.deleteSync();
      }
      
      // Try remove album art
      final artPath = data['albumArt'];
      if (artPath != null && !artPath.startsWith('http')) {
        final file = File(artPath);
        if (file.existsSync()) file.deleteSync();
      }
      
      await box.delete(songId);
    }
  }

  /// Get all downloaded songs as Song objects
  static List<Song> getOfflineSongs() {
    if (!Hive.isBoxOpen('offline_songs')) return [];
    final box = Hive.box('offline_songs');
    final List<Song> songs = [];
    for (var key in box.keys) {
      final data = box.get(key) as Map;
      final songJson = Map<String, dynamic>.from(data);
      songJson['previewUrl'] = data['localPath']; 
      songs.add(SongModel.fromJson(songJson));
    }
    
    // Sort by downloadedAt descending (newest first)
    songs.sort((a, b) {
      final aData = box.get(a.id) as Map?;
      final bData = box.get(b.id) as Map?;
      final aTime = DateTime.tryParse(aData?['downloadedAt']?.toString() ?? '') ?? DateTime.now();
      final bTime = DateTime.tryParse(bData?['downloadedAt']?.toString() ?? '') ?? DateTime.now();
      return bTime.compareTo(aTime);
    });

    return songs;
  }
}
