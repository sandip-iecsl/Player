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
  final String? sourceCodec;
  final int? sourceBitrateKbps;
  final int? sampleRateHz;
  final int? channels;

  const YouTubeAudioFormat({
    required this.quality,
    required this.bitrate,
    required this.format,
    required this.estimatedSizeMb,
    required this.streamUrl,
    required this.formatId,
    this.sourceCodec,
    this.sourceBitrateKbps,
    this.sampleRateHz,
    this.channels,
  });

  bool get isHighQuality =>
      quality == 'High' || bitrate.contains('320') || bitrate.contains('256');
  bool get isMediumQuality =>
      quality == 'Medium' || bitrate.contains('128') || bitrate.contains('160');
  bool get isDataSaver =>
      quality == 'Data Saver' ||
      bitrate.contains('64') ||
      bitrate.contains('48');

  factory YouTubeAudioFormat.fromJson(Map<String, dynamic> json) {
    return YouTubeAudioFormat(
      quality: json['quality']?.toString() ?? 'Medium',
      bitrate: json['bitrate']?.toString() ?? '128 kbps',
      format: json['format']?.toString() ?? 'm4a',
      estimatedSizeMb: json['estimatedSizeMb']?.toString() ?? '3.5 MB',
      streamUrl: json['streamUrl']?.toString() ?? '',
      formatId: json['formatId']?.toString() ?? '139',
      sourceCodec: json['sourceCodec']?.toString(),
      sourceBitrateKbps: (json['sourceBitrateKbps'] as num?)?.toInt(),
      sampleRateHz: (json['sampleRateHz'] as num?)?.toInt(),
      channels: (json['channels'] as num?)?.toInt(),
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
      'sourceCodec': sourceCodec,
      'sourceBitrateKbps': sourceBitrateKbps,
      'sampleRateHz': sampleRateHz,
      'channels': channels,
    };
  }

  /// Helper to estimate file size in MB given bitrate in kbps and duration in seconds
  static String estimateSizeMb(double bitrateKbps, int durationSec) {
    if (durationSec <= 0) return 'Unknown';
    final mb = ((bitrateKbps * 1000 * durationSec) / (8 * 1024 * 1024))
        .toStringAsFixed(1);
    return '$mb MB';
  }

  /// Default predefined fallback tiers
  static List<YouTubeAudioFormat> defaults(
      {required String streamUrl, int durationSec = 180}) {
    final highMb = estimateSizeMb(320, durationSec);
    final medMb = estimateSizeMb(128, durationSec);
    final lowMb = estimateSizeMb(64, durationSec);

    return [
      YouTubeAudioFormat(
        quality: 'High',
        bitrate: '320 kbps',
        format: 'm4a',
        estimatedSizeMb: highMb,
        streamUrl: streamUrl,
        formatId: '140',
      ),
      YouTubeAudioFormat(
        quality: 'Medium',
        bitrate: '128 kbps',
        format: 'm4a',
        estimatedSizeMb: medMb,
        streamUrl: streamUrl,
        formatId: '139',
      ),
      YouTubeAudioFormat(
        quality: 'Data Saver',
        bitrate: '64 kbps',
        format: 'm4a',
        estimatedSizeMb: lowMb,
        streamUrl: streamUrl,
        formatId: '249',
      ),
    ];
  }
}
