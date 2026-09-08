import 'package:flutter/foundation.dart';

/// Represents a standardized audio quality stream/format from YouTube
@immutable
class YouTubeAudioFormat {
  final String quality; // 'High', 'Medium', 'Data Saver'
  final String bitrate; // '320 kbps', '128 kbps', '64 kbps'
  final String format; // 'm4a', 'webm', 'mp4'
  final String estimatedSizeMb; // '9.2 MB', '3.8 MB', '1.9 MB'
  final String streamUrl;
  final String formatId; // '140', '139', '249'

  const YouTubeAudioFormat({
    required this.quality,
    required this.bitrate,
    required this.format,
    required this.estimatedSizeMb,
    required this.streamUrl,
    required this.formatId,
  });

  bool get isHighQuality => quality == 'High' || bitrate.contains('320') || bitrate.contains('256');
  bool get isMediumQuality => quality == 'Medium' || bitrate.contains('128') || bitrate.contains('160');
  bool get isDataSaver => quality == 'Data Saver' || bitrate.contains('64') || bitrate.contains('48');

  factory YouTubeAudioFormat.fromJson(Map<String, dynamic> json) {
    return YouTubeAudioFormat(
      quality: json['quality']?.toString() ?? 'Medium',
      bitrate: json['bitrate']?.toString() ?? '128 kbps',
      format: json['format']?.toString() ?? 'm4a',
      estimatedSizeMb: json['estimatedSizeMb']?.toString() ?? '3.5 MB',
      streamUrl: json['streamUrl']?.toString() ?? '',
      formatId: json['formatId']?.toString() ?? '139',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'quality': quality,
      'bitrate': bitrate,
      'format': format,
      'estimatedSizeMb': estimatedSizeMb,
      'streamUrl': streamUrl,
      'formatId': formatId,
    };
  }

  /// Default predefined fallback tiers
  static List<YouTubeAudioFormat> defaults({required String streamUrl, int durationSec = 180}) {
    final highMb = ((320 * 1000 * durationSec) / (8 * 1024 * 1024)).toStringAsFixed(1);
    final medMb = ((128 * 1000 * durationSec) / (8 * 1024 * 1024)).toStringAsFixed(1);
    final lowMb = ((64 * 1000 * durationSec) / (8 * 1024 * 1024)).toStringAsFixed(1);

    return [
      YouTubeAudioFormat(
        quality: 'High',
        bitrate: '320 kbps',
        format: 'm4a',
        estimatedSizeMb: '$highMb MB',
        streamUrl: streamUrl,
        formatId: '140',
      ),
      YouTubeAudioFormat(
        quality: 'Medium',
        bitrate: '128 kbps',
        format: 'm4a',
        estimatedSizeMb: '$medMb MB',
        streamUrl: streamUrl,
        formatId: '139',
      ),
      YouTubeAudioFormat(
        quality: 'Data Saver',
        bitrate: '64 kbps',
        format: 'm4a',
        estimatedSizeMb: '$lowMb MB',
        streamUrl: streamUrl,
        formatId: '249',
      ),
    ];
  }
}
