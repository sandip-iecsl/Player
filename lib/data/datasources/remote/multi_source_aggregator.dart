import 'dart:math';
import 'package:dio/dio.dart';
import '../../../domain/entities/song.dart';
import 'melo_datasource.dart';

// ── Language priority scoring ─────────────────────────────────────────────────

int _languageScore(Song song) {
  final text = '${song.title} ${song.artist} ${song.album ?? ''}'.toLowerCase();
  // JioSaavn native songs (no platform prefix) = top priority
  final isJio = !song.id.startsWith('yt_') &&
      !song.id.startsWith('dz_') &&
      !song.id.startsWith('it_');
  if (isJio) return 100;
  if (_has(text, [
    'hindi',
    'bollywood',
    'arijit',
    'neha kakkar',
    'atif aslam',
    'jubin',
    'shreya',
    'kumar sanu',
    'kishore',
    'lata',
    'badshah',
    'diljit'
  ])) {
    return 95;
  }
  if (_has(text, ['bengali', 'bangla', 'rabindra', 'anupam roy'])) return 90;
  if (_has(text, ['bhojpuri', 'pawan singh', 'khesari'])) return 85;
  if (_has(text, ['assamese', 'bihu', 'zubeen', 'papon'])) return 75;
  if (_has(text, ['punjabi', 'marathi', 'telugu', 'tamil', 'kannada'])) {
    return 70;
  }
  return 50;
}

bool _has(String t, List<String> kw) => kw.any(t.contains);

/// ┌────────────────────────────────────────────────────────────────────────┐
/// │  PURE JioSaavn Architecture                                            │
/// │                                                                        │
/// │  ALL songs — home sections, trending, search — come from              │
/// │  jiosaavn-api-peach.vercel.app (same as sumitkolhe/jiosaavn-api).      │
/// │                                                                        │
/// │  Each section uses a different `page` number so songs are never       │
/// │  repeated across sections.                                             │
/// └────────────────────────────────────────────────────────────────────────┘
class MultiSourceAggregator {
  final MeloDatasource _melo;

  MultiSourceAggregator({required Dio dio, String youtubeApiKey = ''})
      : _melo = MeloDatasource(dio: dio);

  // ── Public section methods (each uses unique page numbers) ────────────────

  Future<List<Song>> getTrendingMusic() =>
      _melo.getTrendingMusic();

  Future<List<Song>> getGlobalCharts() =>
      _melo.getGlobalCharts();

  Future<List<Song>> getNewReleases() =>
      _melo.getNewReleases();

  Future<List<Song>> getTodaysBiggestHits() =>
      _melo.getTodaysBiggestHits();

  Future<List<Song>> getRecommendedForYou(List<String> genreHints) =>
      _melo.getRecommendedForYou(genreHints);

  Future<List<Song>> getHitsHindi() =>
      _melo.getHitsHindi();

  Future<List<Song>> getRecommendations() =>
      _melo.getRecommendations();

  // ── Vibe sections ──────────────────────────────────────────────────────────

  Future<List<Song>> getLofiChillTracks() =>
      _melo.getLofiChillTracks();

  Future<List<Song>> getDeepFocusTracks() =>
      _melo.getDeepFocusTracks();

  Future<List<Song>> getLateNightVibeTracks() =>
      _melo.getLateNightVibeTracks();

  // ── Smart search (JioSaavn direct — fast & reliable) ─────────────────────

  /// Search fires 3 JioSaavn query variants concurrently for best recall.
  /// Results deduplicated and language-priority sorted.
  Future<List<Song>> searchSongs(String query) async {
    final results = await Future.wait([
      _melo.searchSongs(query, page: 0), // exact
      _melo.searchSongs('$query hindi', page: 0), // Hindi variant
      _melo.searchSongs('$query bollywood', page: 0), // Bollywood variant
    ].map((f) => f.catchError((_) => <Song>[])));

    final seen = <String>{};
    final merged = <Song>[];
    for (final batch in results) {
      for (final s in batch) {
        if (seen.add(s.id)) merged.add(s);
      }
    }
    // Prioritise JioSaavn native songs (no platform prefix)
    merged.sort((a, b) => _languageScore(b).compareTo(_languageScore(a)));
    return merged.take(50).toList();
  }

  // ── Infinite home scroll: section fetcher with rotating pages ─────────────

  /// Used by the home screen's infinite section loader.
  /// [sectionIndex] maps to a unique page so songs are always fresh.
  Future<List<Song>> fetchInfiniteSection(
      String query, int sectionIndex) async {
    // Different page per section index to guarantee unique song sets
    final page = sectionIndex % 10; // pages 0–9 on JioSaavn
    return _melo.searchWithPage(query, page);
  }

  /// Gets suggestions based on a song ID — used for infinite queue.
  Future<List<Song>> getSuggestions(String songId) =>
      _melo.getSuggestions(songId, limit: 15);

}
