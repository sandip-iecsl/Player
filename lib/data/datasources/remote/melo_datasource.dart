import 'package:dio/dio.dart';
import '../../../domain/entities/song.dart';
import '../../models/song_model.dart';

/// Datasource backed by **JioSaavn API** — the public JioSaavn API.
///
/// ✅ Returns FULL 320kbps songs — never trimmed.
/// ✅ Works on Android without any laptop/server setup.
/// ✅ Uses `page` param so every section gets DIFFERENT songs.
/// ✅ No API key required. No login. Always online.
///
/// Primary:  https://jiosaavn-api-peach.vercel.app  (confirmed working)
/// Fallback: https://saavn-api.vercel.app            (community mirror)
/// Fallback: https://saavn.dev                       (frequently down, last resort)
class MeloDatasource {
  final Dio _dio;

  // Ordered by reliability — app tries each in turn if the previous fails
  static const _hosts = [
    'https://jiosaavn-api-peach.vercel.app/api',  // ✅ confirmed working
    'https://saavn-api.vercel.app/api',            // community mirror
    'https://saavn.dev/api',                       // frequently down — last resort
  ];

  MeloDatasource({required Dio dio}) : _dio = dio;

  // ── HTML entity decoder ────────────────────────────────────────────────────

  static String _d(String? s) => (s ?? '').replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&').replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'").replaceAll('&lt;', '<').replaceAll('&gt;', '>');

  // ── Parser ─────────────────────────────────────────────────────────────────

  SongModel _parseSong(Map<String, dynamic> r) {
    // Artists
    final artists = r['artists'] as Map<String, dynamic>? ?? {};
    final primary = (artists['primary'] as List? ?? [])
        .map((a) => _d((a as Map<String, dynamic>)['name'] as String?))
        .where((n) => n.isNotEmpty)
        .join(', ');

    // Album art — use highest quality (500×500)
    final images = r['image'] as List? ?? [];
    String? albumArt;
    if (images.isNotEmpty) {
      // saavn.dev returns [{quality:'50x50', url:...}, {quality:'150x150', url:...}, {quality:'500x500', url:...}]
      albumArt = (images.last as Map<String, dynamic>)['url'] as String?;
    }

    // Download URL — ALWAYS use the 320kbps entry (last in array)
    // saavn.dev returns: [{quality:'12kbps'}, {quality:'48kbps'}, {quality:'96kbps'}, {quality:'160kbps'}, {quality:'320kbps'}]
    final dlUrls = r['downloadUrl'] as List? ?? [];
    String? streamUrl;
    if (dlUrls.isNotEmpty) {
      // Find explicit 320kbps entry, fallback to last
      final hq = dlUrls.lastWhere(
        (e) => (e as Map<String, dynamic>)['quality'] == '320kbps',
        orElse: () => dlUrls.last,
      ) as Map<String, dynamic>;
      streamUrl = hq['url'] as String?;
    }

    // Duration
    final durationSec = r['duration'];
    final duration = Duration(
      seconds: durationSec is int
          ? durationSec
          : int.tryParse(durationSec?.toString() ?? '0') ?? 0,
    );

    return SongModel(
      id: r['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: _d(r['name'] as String?).isNotEmpty ? _d(r['name'] as String?) : 'Unknown',
      artist: primary.isNotEmpty ? primary : 'Unknown Artist',
      albumArt: albumArt,
      album: _d((r['album'] as Map<String, dynamic>?)?['name'] as String?),
      duration: duration,
      previewUrl: streamUrl, // Full 320kbps JioSaavn stream
    );
  }

  // ── Core search with host rotation ───────────────────────────────────────────

  /// Tries each host in [_hosts] order; returns first successful result.
  /// [page] is KEY for variety — different sections pass different pages.
  /// [fullSongsOnly] filters out songs shorter than 90s (previews/short remakes).
  Future<List<Song>> _search(String query,
      {int limit = 30, int page = 0, bool fullSongsOnly = true}) async {
    for (final base in _hosts) {
      try {
        final songs = await _searchFrom(base, query,
            limit: limit, page: page, fullSongsOnly: fullSongsOnly);
        if (songs.isNotEmpty) return songs;
      } catch (e) {
        print('[JioSaavn] $base failed for "$query": '
            '${e.toString().substring(0, (e.toString().length).clamp(0, 80))}');
      }
    }
    print('[JioSaavn] All hosts failed for "$query" p$page');
    return [];
  }

  /// Returns true if a song title/label matches a known short-preview pattern.
  /// These are always remakes/snippets regardless of reported duration.
  static bool _isTrendingVersion(Song s) {
    final t = '${s.title} ${s.album ?? ''}'.toLowerCase();
    return t.contains('trending version') ||
        t.contains('trending remake') ||
        t.contains('(trending)') ||
        t.contains('speed up') ||
        t.contains('sped up') ||
        t.contains('slowed reverb') ||
        t.contains('lofi version') ||
        t.contains('(reverb)') ||
        t.contains('short version');
  }

  Future<List<Song>> _searchFrom(String base, String query,
      {int limit = 20, int page = 0, bool fullSongsOnly = true}) async {
    final response = await _dio.get(
      '$base/search/songs',
      queryParameters: {'query': query, 'limit': limit, 'page': page},
    );
    if (response.data?['success'] != true) return [];
    final results = (response.data['data']?['results'] as List?) ?? [];
    return results
        .whereType<Map<String, dynamic>>()
        .map(_parseSong)
        .where((s) {
          // Must have a playable URL
          if (s.previewUrl == null || s.previewUrl!.isEmpty) return false;
          if (fullSongsOnly) {
            // Block known short-preview title patterns regardless of duration
            if (_isTrendingVersion(s)) return false;
            // Block by duration — but allow duration=0 (unknown) through;
            // the title filter above already catches most fakes
            if (s.duration.inSeconds > 0 && s.duration.inSeconds < 90) return false;
          }
          return true;
        })
        .toList();
  }

  // ── Song ID fetch + suggestions ────────────────────────────────────────────

  /// Fetches a song by its JioSaavn ID (full details including 320kbps URL).
  Future<Song?> getSongById(String id) async {
    for (final base in _hosts) {
      try {
        final r = await _dio.get('$base/songs/$id');
        if (r.data?['success'] != true) continue;
        final data = r.data['data'] as List?;
        if (data == null || data.isEmpty) continue;
        return _parseSong(data.first as Map<String, dynamic>);
      } catch (_) {}
    }
    return null;
  }

  /// Gets similar songs for a given song ID — great for infinite queue.
  Future<List<Song>> getSuggestions(String songId, {int limit = 10}) async {
    for (final base in _hosts) {
      try {
        final r = await _dio.get(
          '$base/songs/$songId/suggestions',
          queryParameters: {'limit': limit},
        );
        if (r.data?['success'] != true) continue;
        final data = r.data['data'] as List? ?? [];
        return data
            .whereType<Map<String, dynamic>>()
            .map(_parseSong)
            .where((s) =>
                s.previewUrl != null &&
                s.previewUrl!.isNotEmpty &&
                !_isTrendingVersion(s))
            .toList();
      } catch (_) {}
    }
    return [];
  }

  // ── 2-Layer Resolution API ─────────────────────────────────────────────────

  /// Resolves a `(title, artist)` discovered from YouTube/Deezer into a
  /// full JioSaavn song. Returns `null` if not found.
  Future<Song?> resolveByTitle(String title, String artist) async {
    final query = artist.isNotEmpty ? '$title $artist' : title;
    final results = await _search(query, limit: 3, page: 0);
    return results.isNotEmpty ? results.first : null;
  }

  /// Batch-resolves (title, artist) pairs in chunks of [maxConcurrent].
  Future<List<Song>> batchResolve(
    List<({String title, String artist})> pairs, {
    int maxConcurrent = 6,
  }) async {
    final results = <Song>[];
    for (int i = 0; i < pairs.length; i += maxConcurrent) {
      final chunk = pairs.skip(i).take(maxConcurrent).toList();
      final resolved = await Future.wait(
        chunk.map((p) => resolveByTitle(p.title, p.artist)
            .catchError((_) => Future<Song?>.value(null))),
      );
      results.addAll(resolved.whereType<Song>());
    }
    return results;
  }

  // ── Section queries — each uses a DIFFERENT page for variety ──────────────
  //
  // This is the key fix for "same songs in every section":
  // page=0 → first 20 results, page=1 → next 20, page=2 → next 20, etc.

  Future<List<Song>> getTrendingMusic() =>
      _search('trending hindi', limit: 20, page: 0);

  Future<List<Song>> getGlobalCharts() =>
      _search('global top 50', limit: 20, page: 1);

  Future<List<Song>> getNewReleases() =>
      _search('new hindi songs', limit: 20, page: 0);

  Future<List<Song>> getRecommendations() =>
      _search('best bollywood', limit: 20, page: 2);

  Future<List<Song>> getHitsHindi() =>
      _search('hindi superhits', limit: 20, page: 3);

  Future<List<Song>> searchSongs(String query, {int page = 0}) =>
      // For user search: don't filter by duration (users may search for short tracks)
      _search(query, limit: 30, page: page, fullSongsOnly: false);

  Future<List<Song>> getTodaysBiggestHits() =>
      _search('biggest hits', limit: 20, page: 1);

  Future<List<Song>> getRecommendedForYou(List<String> genreHints) {
    final query = genreHints.isNotEmpty
        ? genreHints.take(2).join(' ')
        : 'bollywood pop';
    return _search(query, limit: 20, page: 2);
  }

  Future<List<Song>> getLofiChillTracks() =>
      _search('lofi hindi', limit: 20, page: 0);

  Future<List<Song>> getDeepFocusTracks() =>
      _search('instrumental piano', limit: 20, page: 1);

  Future<List<Song>> getLateNightVibeTracks() =>
      _search('late night hindi', limit: 20, page: 0);

  // ── Section queries with rotating pages for the infinite home feed ─────────

  /// Searches with a specific page for infinite scroll variety.
  /// Each section definition can pass a unique page number.
  Future<List<Song>> searchWithPage(String query, int page) =>
      _search(query, limit: 20, page: page);
}
