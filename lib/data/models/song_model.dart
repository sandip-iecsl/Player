import '../../domain/entities/song.dart';

class SongModel extends Song {
  SongModel({
    required super.id,
    required super.title,
    required super.artist,
    super.albumArt,
    super.album,
    required super.duration,
    super.youtubeUrl,
    super.deezerUrl,
    super.previewUrl,
    super.language,
    super.isYoutubeImport,
    super.bitrate,
    super.formatId,
  });

  factory SongModel.fromJson(Map<String, dynamic> json) {
    final durationValue = json['durationMs'] ?? json['duration'] ?? json['duration_ms'];
    int durationMs = 0;
    if (durationValue is num) {
      durationMs = durationValue.toInt();
      if (json['durationMs'] == null && json['duration'] != null) {
        if (durationMs < 10000) {
          durationMs *= 1000;
        }
      }
    } else if (durationValue is String) {
      final parsed = int.tryParse(durationValue) ?? 0;
      if (json['durationMs'] == null && json['duration'] != null) {
        durationMs = parsed < 10000 ? parsed * 1000 : parsed;
      } else {
        durationMs = parsed;
      }
    }

    final songId = json['id']?.toString() ?? '';
    final isYt = json['isYoutubeImport'] == true || songId.startsWith('yt_');

    return SongModel(
      id: songId,
      title: json['title']?.toString() ?? 'Unknown',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      albumArt: json['albumArt']?.toString(),
      album: json['album']?.toString(),
      duration: Duration(milliseconds: durationMs),
      youtubeUrl: json['youtubeUrl']?.toString(),
      deezerUrl: json['deezerUrl']?.toString(),
      previewUrl: json['previewUrl']?.toString(),
      language: json['language']?.toString(),
      isYoutubeImport: isYt,
      bitrate: json['bitrate']?.toString(),
      formatId: json['formatId']?.toString(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'albumArt': albumArt,
      'album': album,
      'duration': duration.inSeconds,
      'durationMs': duration.inMilliseconds,
      'youtubeUrl': youtubeUrl,
      'deezerUrl': deezerUrl,
      'previewUrl': previewUrl,
      'language': language,
      'isYoutubeImport': isYoutubeImport,
      'bitrate': bitrate,
      'formatId': formatId,
    };
  }
}
