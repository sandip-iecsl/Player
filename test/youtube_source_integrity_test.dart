import 'package:flutter_test/flutter_test.dart';
import 'package:aura_player/data/services/youtube_extractor_service.dart';

void main() {
  test('accepts only the exact requested YouTube source identity', () {
    final payload = {
      'source': 'youtube',
      'videoId': 'HAUtFYt46Nc',
      'requestedVideoId': 'HAUtFYt46Nc',
    };

    expect(
      YouTubeExtractorService.hasExactSourceIdentity(payload, 'HAUtFYt46Nc'),
      isTrue,
    );
  });

  test('rejects cross-provider and wrong-video fallback payloads', () {
    expect(
      YouTubeExtractorService.hasExactSourceIdentity({
        'source': 'jiosaavn-fallback',
        'videoId': 'HAUtFYt46Nc',
        'requestedVideoId': 'HAUtFYt46Nc',
      }, 'HAUtFYt46Nc'),
      isFalse,
    );
    expect(
      YouTubeExtractorService.hasExactSourceIdentity({
        'source': 'youtube',
        'videoId': 'differentId1',
        'requestedVideoId': 'differentId1',
      }, 'HAUtFYt46Nc'),
      isFalse,
    );
  });
}
