import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to handle backing up and restoring user-specific data
/// (listening history, preferences, transitions) to Firebase.
///
/// Uses a **debounce + periodic-flush** strategy so Firestore writes are
/// batched:  at most one write per 5 seconds of silence, and at least one
/// write every 30 seconds when data keeps changing – keeping us well inside
/// Firestore's free-tier (50k reads / 20k writes / day for ~10-15 users).
class CloudSyncService {
  static final CloudSyncService _instance = CloudSyncService._internal();
  factory CloudSyncService() => _instance;
  CloudSyncService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _uid;

  // ── Debounce / flush state ────────────────────────────────────────────────
  Timer? _debounceTimer;
  Timer? _maxWaitTimer;
  bool _pendingBackup = false;

  static const _debounceDelay   = Duration(seconds: 5);
  static const _maxFlushDelay   = Duration(seconds: 30);

  // ── Limits (keeps Firestore documents small) ──────────────────────────────
  static const _maxRecentlyPlayed = 30;   // songs
  static const _maxSearchHistory  = 30;   // queries
  static const _maxArtistHistory  = 50;   // artist entries
  static const _maxSongHistory    = 100;  // song play-count entries

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Initialise anonymous auth and restore local data if empty.
  Future<void> init() async {
    try {
      User? user = _auth.currentUser;
      if (user == null) {
        final cred = await _auth.signInAnonymously();
        user = cred.user;
        debugPrint('[CloudSync] Anonymous user signed in: ${user?.uid}');
      } else {
        debugPrint('[CloudSync] Already signed in: ${user.uid}');
      }
      _uid = user?.uid;
      
      // Cache app configuration passcodes locally to avoid future Firestore reads
      try {
        // Always fetch from server — never serve stale cache to the client
        final doc = await _firestore.collection('app_config').doc('map_settings').get(const GetOptions(source: Source.server));
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final prefs = await SharedPreferences.getInstance();
          final adminPasscode = data['adminPasscode']?.toString() ?? data['password']?.toString();

          if (data['appLockPasscode'] != null) {
            await prefs.setString('cached_appLockPasscode', data['appLockPasscode'].toString());
          }
          if (data['secretConsolePasscode'] != null) {
            await prefs.setString('cached_secretConsolePasscode', data['secretConsolePasscode'].toString());
          }
          if (adminPasscode != null && adminPasscode.isNotEmpty) {
            await prefs.setString('cached_adminPasscode', adminPasscode);
          }
          if (data['chatExpiryHours'] is int) {
            await prefs.setInt('cached_chatExpiryHours', data['chatExpiryHours'] as int);
          }
          debugPrint('[CloudSync] 🔑 Configuration passcodes refreshed from live server.');
        }
      } catch (err) {
        debugPrint('[CloudSync] ⚠️ Failed to refresh config from server: $err');
      }

      if (_uid != null) await _restoreDataIfEmpty();
    } catch (e) {
      debugPrint('[CloudSync] ⚠️ init failed: $e');
    }
  }

  /// Schedule a debounced backup.  Multiple rapid calls collapse into one
  /// Firestore write.  Always fires within [_maxFlushDelay] of the first call.
  void backupData() {
    if (_uid == null) return;

    _pendingBackup = true;

    // Debounce: reset the 5-second quiet timer
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, _flushBackup);

    // Max-wait: fire after 30 s even if calls keep coming
    _maxWaitTimer ??= Timer(_maxFlushDelay, _flushBackup);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _flushBackup() async {
    _debounceTimer?.cancel();
    _maxWaitTimer?.cancel();
    _debounceTimer = null;
    _maxWaitTimer  = null;
    if (!_pendingBackup || _uid == null) return;
    _pendingBackup = false;
    await _doBackup();
  }

  // ── Cleaning helpers ──────────────────────────────────────────────────────

  Map<String, dynamic> _cleanSong(Map<String, dynamic> s) => {
    'id':       s['id']?.toString() ?? '',
    'title':    s['title']?.toString() ?? '',
    'artist':   s['artist']?.toString() ?? '',
    'album':    s['album']?.toString() ?? '',
    'albumArt': s['albumArt']?.toString() ?? '',
    'duration': (s['duration'] as num?)?.toInt() ?? 0,
  };

  Map<String, dynamic> _cleanPlaylist(Map<String, dynamic> p) {
    final songs = (p['songs'] as List? ?? [])
        .whereType<Map>()
        .map((s) => _cleanSong(Map<String, dynamic>.from(s)))
        .toList();
    return {
      'id':       p['id']?.toString() ?? '',
      'name':     p['name']?.toString() ?? '',
      'coverUrl': p['coverUrl']?.toString() ?? '',
      'songs':    songs,
    };
  }

  // ── Build "user_profile" analytics summary ────────────────────────────────

  Map<String, dynamic> _buildUserProfile(
    Map artistHistory,
    Map songHistory,
  ) {
    // Top 10 favourite artists by play count
    final topArtists = (artistHistory.entries.toList()
          ..sort((a, b) => (b.value as int).compareTo(a.value as int)))
        .take(10)
        .map((e) => {'artist': e.key, 'count': e.value})
        .toList();

    // Top 10 favourite songs by play count
    final topSongs = (songHistory.entries.toList()
          ..sort((a, b) => (b.value as int).compareTo(a.value as int)))
        .take(10)
        .map((e) => {'id': e.key, 'count': e.value})
        .toList();

    return {
      'topArtists':    topArtists,
      'topSongs':      topSongs,
      'totalPlays':    (songHistory.values.fold<int>(0, (s, v) => s + (v as int? ?? 0))),
      'uniqueSongs':   songHistory.length,
      'uniqueArtists': artistHistory.length,
      'updatedAt':     FieldValue.serverTimestamp(),
    };
  }

  // ── Prune oversized maps to stay within document limits ───────────────────

  Map<String, dynamic> _pruneMap(Map raw, int maxEntries) {
    if (raw.length <= maxEntries) return Map<String, dynamic>.from(raw);
    // Keep the entries with the highest values (play counts)
    final sorted = raw.entries.toList()
      ..sort((a, b) => (b.value as int? ?? 0).compareTo(a.value as int? ?? 0));
    return Map.fromEntries(sorted.take(maxEntries).map((e) => MapEntry(e.key.toString(), e.value)));
  }

  // ── Core backup ───────────────────────────────────────────────────────────

  Future<void> _doBackup() async {
    if (_uid == null) return;
    try {
      final historyBox     = Hive.box('listening_history');
      final transitionsBox = Hive.box('track_transitions');
      final recentlyBox    = Hive.isBoxOpen('recentlyPlayed')
          ? Hive.box<String>('recentlyPlayed')
          : await Hive.openBox<String>('recentlyPlayed');
      final searchBox      = Hive.isBoxOpen('searchHistory')
          ? Hive.box<String>('searchHistory')
          : await Hive.openBox<String>('searchHistory');
      final playlistsBox   = Hive.isBoxOpen('userPlaylists')
          ? Hive.box<String>('userPlaylists')
          : await Hive.openBox<String>('userPlaylists');

      // ── Raw maps ──────────────────────────────────────────────────────────
      final Map artistHistoryRaw = historyBox.get('artists', defaultValue: {}) as Map;
      final Map songHistoryRaw   = historyBox.get('songs',   defaultValue: {}) as Map;

      // Prune to keep document size manageable
      final artistHistory = _pruneMap(artistHistoryRaw, _maxArtistHistory);
      final songHistory   = _pruneMap(songHistoryRaw,   _maxSongHistory);

      // ── Transitions ───────────────────────────────────────────────────────
      final transitionsData = <String, dynamic>{};
      for (final key in transitionsBox.keys) {
        transitionsData[key.toString()] = transitionsBox.get(key);
      }

      // ── Recently played ───────────────────────────────────────────────────
      final recentlyPlayedList = <Map<String, dynamic>>[];
      for (final val in recentlyBox.values) {
        try {
          final decoded = jsonDecode(val);
          if (decoded is Map) {
            recentlyPlayedList.add(_cleanSong(Map<String, dynamic>.from(decoded)));
          }
        } catch (_) {}
      }
      // Keep most-recent N
      final trimmedRecentlyPlayed = recentlyPlayedList.length > _maxRecentlyPlayed
          ? recentlyPlayedList.sublist(recentlyPlayedList.length - _maxRecentlyPlayed)
          : recentlyPlayedList;

      // ── Search history ────────────────────────────────────────────────────
      final searchHistory = searchBox.values
          .toList()
          .reversed
          .take(_maxSearchHistory)
          .toList();

      // ── Playlists ─────────────────────────────────────────────────────────
      final playlistsData = <String, dynamic>{};
      for (final key in playlistsBox.keys) {
        final val = playlistsBox.get(key);
        if (val is String) {
          try {
            final decoded = jsonDecode(val);
            if (decoded is Map) {
              playlistsData[key.toString()] =
                  _cleanPlaylist(Map<String, dynamic>.from(decoded));
            }
          } catch (_) {}
        }
      }

      // ── User profile (analytics summary for recommendation engine) ────────
      final userProfile = _buildUserProfile(artistHistoryRaw, songHistoryRaw);

      debugPrint('[CloudSync] ☁️ Uploading – '
          'recently=${trimmedRecentlyPlayed.length}, '
          'search=${searchHistory.length}, '
          'artists=${artistHistory.length}, '
          'songs=${songHistory.length}, '
          'playlists=${playlistsData.length}');

      await _firestore.collection('users').doc(_uid).set({
        'listening_history': {
          'artists': artistHistory,
          'songs':   songHistory,
        },
        'track_transitions':  transitionsData,
        'recently_played':    trimmedRecentlyPlayed,
        'search_history':     searchHistory,
        'user_playlists':     playlistsData,
        'user_profile':       userProfile,
        'last_sync':          FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('[CloudSync] ✅ Backup complete.');
    } catch (e) {
      debugPrint('[CloudSync] ⚠️ Backup failed: $e');
      _pendingBackup = true; // retry on next trigger
    }
  }

  // ── Restore ───────────────────────────────────────────────────────────────

  /// Restores data from Firebase to local Hive storage if local storage is empty.
  Future<void> _restoreDataIfEmpty() async {
    if (_uid == null) return;
    try {
      final historyBox     = Hive.box('listening_history');
      final transitionsBox = Hive.box('track_transitions');
      final recentlyBox    = Hive.isBoxOpen('recentlyPlayed')
          ? Hive.box<String>('recentlyPlayed')
          : await Hive.openBox<String>('recentlyPlayed');
      final searchBox      = Hive.isBoxOpen('searchHistory')
          ? Hive.box<String>('searchHistory')
          : await Hive.openBox<String>('searchHistory');
      final playlistsBox   = Hive.isBoxOpen('userPlaylists')
          ? Hive.box<String>('userPlaylists')
          : await Hive.openBox<String>('userPlaylists');

      if (historyBox.isEmpty && transitionsBox.isEmpty &&
          recentlyBox.isEmpty && searchBox.isEmpty && playlistsBox.isEmpty) {
        debugPrint('[CloudSync] Local empty – restoring from cloud…');
        final doc = await _firestore.collection('users').doc(_uid).get().timeout(const Duration(seconds: 5));
        if (!doc.exists || doc.data() == null) {
          debugPrint('[CloudSync] No cloud data found.');
          return;
        }
        final data = doc.data()!;

        // listening_history (new nested format)
        if (data['listening_history'] is Map) {
          final h = data['listening_history'] as Map<String, dynamic>;
          if (h['artists'] != null) await historyBox.put('artists', h['artists']);
          if (h['songs']   != null) await historyBox.put('songs',   h['songs']);
        }

        // track_transitions
        if (data['track_transitions'] is Map) {
          for (final e in (data['track_transitions'] as Map).entries) {
            await transitionsBox.put(e.key, e.value);
          }
        }

        // recently_played
        if (data['recently_played'] is List) {
          await recentlyBox.clear();
          for (final item in data['recently_played'] as List) {
            if (item is Map) {
              final s = Map<String, dynamic>.from(item);
              s['previewUrl']  = '';
              s['youtubeUrl']  = '';
              s['deezerUrl']   = '';
              await recentlyBox.add(jsonEncode(s));
            }
          }
        }

        // search_history
        if (data['search_history'] is List) {
          await searchBox.clear();
          for (final q in data['search_history'] as List) {
            await searchBox.add(q.toString());
          }
        }

        // user_playlists
        if (data['user_playlists'] is Map) {
          for (final e in (data['user_playlists'] as Map).entries) {
            if (e.value is Map) {
              final p = Map<String, dynamic>.from(e.value as Map);
              final songs = (p['songs'] as List? ?? []).map((s) {
                if (s is Map) {
                  final sm = Map<String, dynamic>.from(s);
                  sm['previewUrl'] = '';
                  sm['youtubeUrl'] = '';
                  sm['deezerUrl']  = '';
                  return sm;
                }
                return s;
              }).toList();
              p['songs'] = songs;
              await playlistsBox.put(e.key, jsonEncode(p));
            }
          }
        }

        debugPrint('[CloudSync] ✅ Restore complete.');
      }
    } catch (e) {
      debugPrint('[CloudSync] ⚠️ Restore failed: $e');
    }
  }
}
