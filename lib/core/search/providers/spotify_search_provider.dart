import 'package:flutter/foundation.dart';
import '../../../data/services/spotify_client_service.dart';
import '../models/search_models.dart';
import 'provider_health.dart';
import 'search_provider.dart';

/// Provider 7: Spotify Metadata & Search Provider
/// Authorized discovery & track metadata retrieval
class SpotifySearchProvider implements SearchProviderClient {
  @override
  final SearchProviderType provider = SearchProviderType.spotify;

  @override
  final ProviderHealth health = ProviderHealth(provider: SearchProviderType.spotify);

  @override
  bool get isEnabled => true;

  @override
  int get priority => 7;

  @override
  Duration get timeout => const Duration(seconds: 4);

  final SpotifyClientService _spotifyService;

  SpotifySearchProvider({SpotifyClientService? spotifyService})
      : _spotifyService = spotifyService ?? SpotifyClientService();

  @override
  Future<List<SearchCandidate>> search(
    ParsedQuery query,
    SearchRequest request,
  ) async {
    if (!health.isAvailable) {
      debugPrint('[SpotifySearchProvider] ⚡ Circuit OPEN. Skipping request.');
      return [];
    }

    final stopwatch = Stopwatch()..start();
    try {
      final q = query.effectiveQuery;
      final tracks = await _spotifyService.searchTracks(q, limit: request.limit).timeout(timeout);

      stopwatch.stop();

      final candidates = tracks.map((t) {
        return SearchCandidate(
          canonicalId: 'spotify_${t.id}',
          spotifyId: t.id,
          title: t.name,
          artist: t.artist,
          album: t.album,
          normalizedTitle: t.name.toLowerCase().trim(),
          normalizedArtist: t.artist.toLowerCase().trim(),
          normalizedAlbum: t.album.toLowerCase().trim(),
          duration: Duration(milliseconds: t.durationMs),
          versionType: _inferVersionType(t.name),
          sourceProvider: SearchProviderType.spotify,
          popularityScore: (t.popularity / 100.0).clamp(0.0, 1.0),
          artworkUrl: t.albumArt,
          playableUrl: t.previewUrl,
          previewUrl: t.previewUrl,
          isDownloadable: false, // Spotify API is metadata-only
          audioFormat: 'mp3',
          bitrate: '160 kbps',
          providerMetadata: {
            'provider': 'spotify',
            'id': t.id,
            'spotify_url': t.spotifyUrl,
            'popularity': t.popularity,
          },
          matchedProviders: [SearchProviderType.spotify],
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
      debugPrint('[SpotifySearchProvider] ⚠️ Spotify search error: $e');
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
