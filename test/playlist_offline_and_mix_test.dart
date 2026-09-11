import 'package:flutter_test/flutter_test.dart';
import 'package:aura_player/data/services/youtube_extractor_service.dart';
import 'package:aura_player/domain/entities/song.dart';
import 'package:aura_player/presentation/providers/playlist_provider.dart';

void main() {
  group('YouTube Mix, Radio & Playlist Sanitization Tests', () {
    test('Correctly parses and sanitizes dynamic YouTube Mix link (list=RD...)', () {
      const rawMixUrl = 'https://youtube.com/playlist?list=RD_JL6JAf-HKw&playnext=1&si=2RJIIOcIUEcSzI7H';
      
      final sanitized = YouTubeExtractorService.sanitizeYouTubeLink(rawMixUrl);
      
      // Should strip playnext, si and attach seed video ID
      expect(sanitized, contains('watch?v=_JL6JAf-HKw'));
      expect(sanitized, contains('list=RD_JL6JAf-HKw'));
      expect(sanitized, isNot(contains('playnext')));
      expect(sanitized, isNot(contains('si=')));
      
      // Video ID extraction
      final videoId = YouTubeExtractorService.extractVideoId(rawMixUrl);
      expect(videoId, equals('_JL6JAf-HKw'));
      
      // isYouTubeUrl verification
      expect(YouTubeExtractorService.isYouTubeUrl(rawMixUrl), isTrue);
    });

    test('Sanitizes tracking query params from standard YouTube & YouTube Music URLs', () {
      const trackingUrl = 'https://www.youtube.com/watch?v=kJQP7kiw5Fk&feature=share&si=abc1234&pp=ygUIZGVzcGFjaXRv';
      final sanitized = YouTubeExtractorService.sanitizeYouTubeLink(trackingUrl);
      
      expect(sanitized, contains('watch?v=kJQP7kiw5Fk'));
      expect(sanitized, isNot(contains('feature')));
      expect(sanitized, isNot(contains('si=')));
      expect(sanitized, isNot(contains('pp=')));
      expect(YouTubeExtractorService.extractVideoId(trackingUrl), equals('kJQP7kiw5Fk'));
    });

    test('Extracts video ID from youtu.be and shorts links', () {
      const shortUrl = 'https://youtu.be/fJ9rUzIMcZQ?si=XYZ999';
      expect(YouTubeExtractorService.extractVideoId(shortUrl), equals('fJ9rUzIMcZQ'));

      const shortsUrl = 'https://www.youtube.com/shorts/3nQNiWdeH2Q';
      expect(YouTubeExtractorService.extractVideoId(shortsUrl), equals('3nQNiWdeH2Q'));

      const embedUrl = 'https://www.youtube.com/embed/dQw4w9WgXcQ';
      expect(YouTubeExtractorService.extractVideoId(embedUrl), equals('dQw4w9WgXcQ'));

      const directId = 'fJ9rUzIMcZQ';
      expect(YouTubeExtractorService.extractVideoId(directId), equals('fJ9rUzIMcZQ'));
    });

    test('enforceStrictVideoUrl produces clean canonical watch URLs without playlist drift', () {
      const mixUrl = 'https://youtube.com/playlist?list=RD_JL6JAf-HKw&playnext=1';
      final cleanUrl = YouTubeExtractorService.enforceStrictVideoUrl(mixUrl);
      expect(cleanUrl, equals('https://www.youtube.com/watch?v=_JL6JAf-HKw'));

      const shortsUrl = 'https://www.youtube.com/shorts/3nQNiWdeH2Q';
      final cleanShorts = YouTubeExtractorService.enforceStrictVideoUrl(shortsUrl);
      expect(cleanShorts, equals('https://www.youtube.com/watch?v=3nQNiWdeH2Q'));
    });
  });

  group('Hybrid Offline Playlist & Serialization Resilience', () {
    test('Song model retains bitrate, formatId, and previewUrl across JSON roundtrip', () {
      final original = Song(
        id: 'yt__JL6JAf-HKw',
        title: 'Master Track',
        artist: 'Featured Artist',
        duration: const Duration(seconds: 215),
        previewUrl: '/data/user/0/com.example.aura/app_flutter/offline_yt__JL6JAf-HKw.m4a',
        isYoutubeImport: true,
        bitrate: '320 kbps',
        formatId: '140',
      );

      final json = original.toJson();
      final restored = Song.fromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.title, equals(original.title));
      expect(restored.isYoutubeImport, isTrue);
      expect(restored.bitrate, equals('320 kbps'));
      expect(restored.formatId, equals('140'));
      expect(restored.previewUrl, equals(original.previewUrl));
    });

    test('Playlist entity serializes mixed offline and online songs faithfully', () {
      final offlineSong = Song(
        id: 'offline_1',
        title: 'Offline Banger',
        artist: 'Local Hero',
        duration: const Duration(seconds: 180),
        previewUrl: '/storage/emulated/0/Music/song1.mp3',
      );

      final onlineSong = Song(
        id: 'online_1',
        title: 'Cloud Stream',
        artist: 'Online Artist',
        duration: const Duration(seconds: 200),
        previewUrl: 'https://aac.saavncdn.com/song2.mp4',
      );

      final playlist = Playlist(
        id: 'custom_playlist_1',
        name: 'Hybrid Mix',
        songs: [offlineSong, onlineSong],
      );

      final json = playlist.toJson();
      final restored = Playlist.fromJson(json);

      expect(restored.songs.length, equals(2));
      expect(restored.songs[0].previewUrl, equals('/storage/emulated/0/Music/song1.mp3'));
      expect(restored.songs[1].previewUrl, equals('https://aac.saavncdn.com/song2.mp4'));
    });
  });
}
