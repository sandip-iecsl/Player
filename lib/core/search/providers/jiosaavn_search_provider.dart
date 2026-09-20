import 'package:flutter/foundation.dart';
import '../../../data/services/direct_jiosaavn_service.dart';
import '../models/search_models.dart';
import 'provider_health.dart';
import 'search_provider.dart';

/// Provider 4: JioSaavn Stream & Search Provider
/// Wraps direct JioSaavn search and stream URL decryption
class JioSaavnSearchProvider implements SearchProviderClient {
  @override
  final SearchProviderType provider = SearchProviderType.jiosaavn;

  @override
  final ProviderHealth health = ProviderHealth(provider: SearchProviderType.jiosaavn);

  @override
  bool get isEnabled => true;

  @override
  int get priority => 4;

  @override
  Duration get timeout => const Duration(seconds: 5);

  final DirectJioSaavnService _service;

  JioSaavnSearchProvider({DirectJioSaavnService? service})
      : _service = service ?? DirectJioSaavnService();

  @override
  Future<List<SearchCandidate>> search(
    ParsedQuery query,
    SearchRequest request,
  ) async {
    if (!health.isAvailable) {
      debugPrint('[JioSaavnSearchProvider] ⚡ Circuit OPEN. Skipping request.');
      return [];
    }

    final stopwatch = Stopwatch()..start();
    try {
      final q = query.effectiveQuery;
      final songs = await _service.searchSongs(q, limit: request.limit, page: request.page).timeout(timeout);

      stopwatch.stop();

      final candidates = songs.map((s) {
        return SearchCandidate(
          canonicalId: 'saavn_${s.id}',
          jioSaavnId: s.id,
          title: s.title,
          artist: s.artist,
          album: s.album,
          normalizedTitle: s.title.toLowerCase().trim(),
          normalizedArtist: s.artist.toLowerCase().trim(),
          normalizedAlbum: s.album?.toLowerCase().trim(),
          duration: s.duration,
          language: s.language,
          versionType: _inferVersionType(s.title),
          sourceProvider: SearchProviderType.jiosaavn,
          artworkUrl: s.albumArt,
          playableUrl: s.previewUrl,
          previewUrl: s.previewUrl,
          bitrate: s.bitrate ?? '320 kbps',
          isDownloadable: true,
          providerMetadata: {
            'provider': 'jiosaavn',
            'id': s.id,
            'has_stream': s.previewUrl != null && s.previewUrl!.isNotEmpty,
          },
          matchedProviders: const [SearchProviderType.jiosaavn],
        );
      }).toList();

      health.recordSuccess(stopwatch.elapsed);
      return candidates;
    } catch (e) {
      stopwatch.stop();
      final isTimeout = e.toString().contains('TimeoutException');
      final is429 = e.toString().contains('429');
      health.recordFailure(
        error: e.toString(),
        isTimeout: isTimeout,
        isRateLimit: is429,
        isHttpError: !isTimeout && !is429,
      );
      debugPrint('[JioSaavnSearchProvider] ⚠️ Error searching JioSaavn: $e');
      return [];
    }
  }

  TrackVersionType _inferVersionType(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('remix')) return TrackVersionType.remix;
    if (lower.contains('live')) return TrackVersionType.live;
    if (lower.contains('acoustic')) return TrackVersionType.acoustic;
    if (lower.contains('cover')) return TrackVersionType.cover;
    if (lower.contains('slowed') || lower.contains('reverb')) return TrackVersionType.slowed;
    if (lower.contains('lofi') || lower.contains('lo-fi')) return TrackVersionType.lofi;
    return TrackVersionType.official;
  }
}
