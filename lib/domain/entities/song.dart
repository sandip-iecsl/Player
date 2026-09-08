class Song {
  final String id;
  final String title;
  final String artist;
  final String? albumArt;
  final String? album;
  final Duration duration;
  final String? youtubeUrl;
  final String? deezerUrl;
  final String? previewUrl; // Direct 30s MP3 stream from Deezer
  final String? language;
  final bool isYoutubeImport;
  final String? bitrate;
  final String? formatId;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    this.albumArt,
    this.album,
    required this.duration,
    this.youtubeUrl,
    this.deezerUrl,
    this.previewUrl,
    this.language,
    this.isYoutubeImport = false,
    this.bitrate,
    this.formatId,
  });

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

  factory Song.fromJson(Map<String, dynamic> json) {
    final durationValue = json['durationMs'] ?? json['duration'] ?? json['duration_ms'];
    int durationMs = 0;
    if (durationValue is num) {
      durationMs = durationValue.toInt();
      if (json['durationMs'] == null && json['duration'] != null) {
        // If only `duration` is present, treat it as seconds unless the value is large enough
        // to clearly represent milliseconds.
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

    final songId = json['id'] as String? ?? '';
    final isYt = json['isYoutubeImport'] == true || songId.startsWith('yt_');

    return Song(
      id: songId,
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      albumArt: json['albumArt'] as String?,
      album: json['album'] as String?,
      duration: Duration(milliseconds: durationMs),
      youtubeUrl: json['youtubeUrl'] as String?,
      deezerUrl: json['deezerUrl'] as String?,
      previewUrl: json['previewUrl'] as String?,
      language: json['language'] as String?,
      isYoutubeImport: isYt,
      bitrate: json['bitrate'] as String?,
      formatId: json['formatId'] as String?,
    );
  }

  /// Returns a copy of this Song with the given fields replaced.
  /// Used to update stale CDN URLs in the queue without mutating the original.
  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? albumArt,
    String? album,
    Duration? duration,
    String? youtubeUrl,
    String? deezerUrl,
    String? previewUrl,
    String? language,
    bool? isYoutubeImport,
    String? bitrate,
    String? formatId,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      albumArt: albumArt ?? this.albumArt,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      deezerUrl: deezerUrl ?? this.deezerUrl,
      previewUrl: previewUrl ?? this.previewUrl,
      language: language ?? this.language,
      isYoutubeImport: isYoutubeImport ?? this.isYoutubeImport,
      bitrate: bitrate ?? this.bitrate,
      formatId: formatId ?? this.formatId,
    );
  }
}
