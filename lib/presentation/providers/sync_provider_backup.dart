import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../domain/entities/song.dart';
import '../providers/audio_provider.dart';
import '../providers/lock_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

enum SyncStatus { idle, hosting, joined, error }

class Endpoint {
  final String id;
  final String name;
  Endpoint(this.id, this.name);
}

class SyncState {
  final String? roomId;
  final SyncStatus status;
  final String? errorMessage;
  final String? hostName;
  final List<String> connectedUsers;
  final List<Endpoint> discoveredEndpoints;
  final Map<String, String> connectedEndpoints; // endpointId -> displayName
  final String? roomPassword;
  final bool isPasswordVerified;
  final bool isSyncing;
  final Map<String, bool> readyEndpoints;

  const SyncState({
    this.roomId,
    this.status = SyncStatus.idle,
    this.errorMessage,
    this.hostName,
    this.connectedUsers = const [],
    this.discoveredEndpoints = const [],
    this.connectedEndpoints = const {},
    this.roomPassword,
    this.isPasswordVerified = false,
    this.isSyncing = false,
    this.readyEndpoints = const {},
  });

  bool get isActive => status == SyncStatus.hosting || status == SyncStatus.joined;
  bool get isHost => status == SyncStatus.hosting;

  SyncState copyWith({
    String? roomId,
    SyncStatus? status,
    String? errorMessage,
    String? hostName,
    List<String>? connectedUsers,
    List<Endpoint>? discoveredEndpoints,
    Map<String, String>? connectedEndpoints,
    String? roomPassword,
    bool? isPasswordVerified,
    bool? isSyncing,
    Map<String, bool>? readyEndpoints,
  }) =>
      SyncState(
        roomId: roomId ?? this.roomId,
        status: status ?? this.status,
        errorMessage: errorMessage,
        hostName: hostName ?? this.hostName,
        connectedUsers: connectedUsers ?? this.connectedUsers,
        discoveredEndpoints: discoveredEndpoints ?? this.discoveredEndpoints,
        connectedEndpoints: connectedEndpoints ?? this.connectedEndpoints,
        roomPassword: roomPassword ?? this.roomPassword,
        isPasswordVerified: isPasswordVerified ?? this.isPasswordVerified,
        isSyncing: isSyncing ?? this.isSyncing,
        readyEndpoints: readyEndpoints ?? this.readyEndpoints,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final syncProvider =
    StateNotifierProvider<SyncNotifier, SyncState>((ref) => SyncNotifier(ref));

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  final Strategy _strategy = Strategy.P2P_STAR;

  ProviderSubscription? _songSub;
  ProviderSubscription? _playingSub;
  Timer? _syncTimer;

  // Guard: prevents re-broadcasting events that we ourselves triggered
  bool _suppressBroadcast = false;

  SyncNotifier(this._ref) : super(const SyncState());

  // ── HOST ──────────────────────────────────────────────────────────────────

  Future<void> createRoom(String password) async {
    try {
      final myName = _ref.read(lockProvider).userName ?? 'Host';

      await _requestPermissions(isHost: true);
      await Nearby().stopAdvertising();

      final running = await Nearby().startAdvertising(
        myName,
        _strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: 'com.example.free_play.aura',
      );

      if (running) {
        state = state.copyWith(
          roomId: myName,
          status: SyncStatus.hosting,
          hostName: myName,
          connectedUsers: [],
          errorMessage: null,
          roomPassword: password,
          isPasswordVerified: true,
        );
        _startHostListeners();
        print('[Sync] 🎙️ Room created: $myName');
      } else {
        state = state.copyWith(
            status: SyncStatus.error, errorMessage: 'Failed to start advertising.');
      }
    } catch (e) {
      state = state.copyWith(status: SyncStatus.error, errorMessage: 'Error: $e');
    }
  }

  // ── GUEST ─────────────────────────────────────────────────────────────────

  Future<void> startDiscovery() async {
    state = state.copyWith(discoveredEndpoints: [], errorMessage: null);
    try {
      await _requestPermissions(isHost: false);
      await Nearby().stopDiscovery();
      await Nearby().startDiscovery(
        _ref.read(lockProvider).userName ?? 'Guest',
        _strategy,
        onEndpointFound: (id, name, serviceId) {
          final list = List<Endpoint>.from(state.discoveredEndpoints);
          if (!list.any((e) => e.id == id)) {
            list.add(Endpoint(id, name));
            state = state.copyWith(discoveredEndpoints: list);
          }
        },
        onEndpointLost: (id) {
          final list = List<Endpoint>.from(state.discoveredEndpoints)
            ..removeWhere((e) => e.id == id);
          state = state.copyWith(discoveredEndpoints: list);
        },
        serviceId: 'com.example.free_play.aura',
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Discovery error: $e');
    }
  }

  Future<void> joinRoom(Endpoint endpoint, String password) async {
    try {
      await Nearby().stopDiscovery();
      state = state.copyWith(roomPassword: password, isPasswordVerified: false);
      await Nearby().requestConnection(
        _ref.read(lockProvider).userName ?? 'Guest',
        endpoint.id,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Join error: $e');
    }
  }

  // ── Connection callbacks ──────────────────────────────────────────────────

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: _onPayloadReceived,
      onPayloadTransferUpdate: (_, __) {},
    );
  }

  void _onConnectionResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      print('[Sync] ✅ Connected: $id');
      if (!state.isHost) {
        // Guest: send password immediately
        final myName = _ref.read(lockProvider).userName ?? 'Guest';
        _send(id, {'type': 'auth_password', 'value': state.roomPassword, 'name': myName});
        final ep = state.discoveredEndpoints.firstWhere(
          (e) => e.id == id,
          orElse: () => Endpoint(id, 'Host'),
        );
        state = state.copyWith(status: SyncStatus.joined, hostName: ep.name);
      }
    } else {
      print('[Sync] ❌ Connection failed: $id status=$status');
    }
  }

  void _onDisconnected(String id) {
    print('[Sync] 💔 Disconnected: $id');
    final newConn = Map<String, String>.from(state.connectedEndpoints)..remove(id);
    final newReady = Map<String, bool>.from(state.readyEndpoints)..remove(id);
    state = state.copyWith(
      connectedEndpoints: newConn,
      connectedUsers: newConn.values.toList(),
      readyEndpoints: newReady,
    );
    if (!state.isHost && newConn.isEmpty) stopSync();
  }

  // ── Payload handler ───────────────────────────────────────────────────────

  void _onPayloadReceived(String fromId, Payload payload) async {
    if (payload.type != PayloadType.BYTES) return;
    try {
      final data = jsonDecode(utf8.decode(payload.bytes!)) as Map<String, dynamic>;
      final type = data['type'] as String?;

      // ── AUTH: Guest → Host ──────────────────────────────────────────────
      if (type == 'auth_password' && state.isHost) {
        if (data['value'] == state.roomPassword) {
          final newConn = Map<String, String>.from(state.connectedEndpoints)
            ..[fromId] = data['name'] as String? ?? 'Friend';
          state = state.copyWith(
            connectedEndpoints: newConn,
            connectedUsers: newConn.values.toList(),
          );
          _send(fromId, {'type': 'auth_ok'});
          print('[Sync] 🔑 Auth OK for $fromId');

          // Send current song state to newly joined guest
          final song = _ref.read(audioServiceProvider).currentSong;
          if (song != null) {
            final pos = _ref.read(currentPositionProvider).valueOrNull ?? Duration.zero;
            final isPlaying = _ref.read(isPlayingProvider).valueOrNull ?? false;
            _sendPrepare(fromId, song, pos.inMilliseconds, autoPlay: isPlaying);
          }
        } else {
          print('[Sync] 🚫 Wrong password from $fromId');
          Nearby().disconnectFromEndpoint(fromId);
        }
        return;
      }

      // ── AUTH OK: Host → Guest ───────────────────────────────────────────
      if (type == 'auth_ok') {
        state = state.copyWith(isPasswordVerified: true);
        print('[Sync] ✅ Password verified by host');
        return;
      }

      if (!state.isPasswordVerified && !state.isHost) return;

      // ── PREPARE: Host → Guest ───────────────────────────────────────────
      if (type == 'sync_prepare') {
        await _handlePrepare(fromId, data);
        return;
      }

      // ── READY: Guest → Host ─────────────────────────────────────────────
      if (type == 'sync_ready' && state.isHost) {
        final newReady = Map<String, bool>.from(state.readyEndpoints)..[fromId] = true;
        state = state.copyWith(readyEndpoints: newReady);
        print('[Sync] 👍 Ready from $fromId (${newReady.length}/${state.connectedEndpoints.length})');

        // All clients ready → send coordinated start
        if (newReady.length >= state.connectedEndpoints.length) {
          _broadcastSyncStart();
        }
        return;
      }

      // ── START: Host → Guest ─────────────────────────────────────────────
      if (type == 'sync_start') {
        final startAt = data['startAt'] as int;
        final posMs = data['positionMs'] as int;
        _schedulePlay(startAt, posMs);
        return;
      }

      // ── PAUSE: Host → Guest ─────────────────────────────────────────────
      if (type == 'sync_pause') {
        _suppressBroadcast = true;
        await _ref.read(audioServiceProvider).pause();
        _suppressBroadcast = false;
        return;
      }

      // ── SEEK: Host → Guest ──────────────────────────────────────────────
      if (type == 'sync_seek') {
        final posMs = data['positionMs'] as int;
        _suppressBroadcast = true;
        await _ref.read(audioServiceProvider).seek(Duration(milliseconds: posMs));
        _suppressBroadcast = false;
        return;
      }

    } catch (e) {
      print('[Sync] ⚠️ Payload error: $e');
    }
  }

  // ── PREPARE handler (guest side) ─────────────────────────────────────────

  Future<void> _handlePrepare(String fromId, Map<String, dynamic> data) async {
    state = state.copyWith(isSyncing: true);
    final songData = data['song'] as Map<String, dynamic>;
    final posMs = data['positionMs'] as int;
    final autoPlay = data['autoPlay'] as bool? ?? true;

    print('[Sync] 📥 Prepare: ${songData['title']} @ ${posMs}ms autoPlay=$autoPlay');

    final audio = _ref.read(audioServiceProvider);
    _suppressBroadcast = true;

    try {
      final song = Song(
        id: songData['id'] ?? 'sync_song',
        title: songData['title'] ?? 'Unknown',
        artist: songData['artist'] ?? 'Unknown',
        album: songData['album'],
        albumArt: songData['albumArt'],
        duration: Duration(milliseconds: songData['durationMs'] ?? 0),
        previewUrl: songData['previewUrl'],
      );

      await audio.pause();
      await audio.loadQueue([song], startIndex: 0);
      // Wait for player to be ready before seeking
      await Future.delayed(const Duration(milliseconds: 400));
      await audio.seek(Duration(milliseconds: posMs));
      await audio.pause(); // ensure paused while waiting for sync_start
    } finally {
      _suppressBroadcast = false;
    }

    state = state.copyWith(isSyncing: autoPlay);

    if (autoPlay) {
      // Tell host we're ready
      _send(fromId, {'type': 'sync_ready'});
    } else {
      // Not playing — just stay paused, no need for coordinated start
      state = state.copyWith(isSyncing: false);
    }
  }

  // ── Host listeners ────────────────────────────────────────────────────────

  void _startHostListeners() {
    String? lastSongId;

    // Song change → broadcast prepare to all guests
    _songSub = _ref.listen<AsyncValue<Song?>>(currentSongProvider, (prev, next) {
      if (_suppressBroadcast) return;
      final song = next.valueOrNull;
      if (song == null || !state.isHost || state.connectedEndpoints.isEmpty) return;
      if (song.id == lastSongId) return; // same song, skip
      lastSongId = song.id;

      // Small delay to let audio service settle on the new song
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        final currentSong = _ref.read(audioServiceProvider).currentSong;
        if (currentSong == null) return;
        _broadcastPrepare(currentSong, 0, autoPlay: true);
      });
    });

    // Play/Pause → broadcast to guests
    _playingSub = _ref.listen<AsyncValue<bool>>(isPlayingProvider, (prev, next) {
      if (_suppressBroadcast) return;
      if (!state.isHost || state.connectedEndpoints.isEmpty) return;
      final isPlaying = next.valueOrNull ?? false;
      final wasPlaying = prev?.valueOrNull ?? false;
      if (isPlaying == wasPlaying) return;

      if (isPlaying) {
        // Host resumed → trigger full sync handshake
        final song = _ref.read(audioServiceProvider).currentSong;
        if (song == null) return;
        final pos = _ref.read(currentPositionProvider).valueOrNull ?? Duration.zero;
        _broadcastPrepare(song, pos.inMilliseconds, autoPlay: true);
      } else {
        // Host paused → tell all guests to pause immediately
        _broadcastAll({'type': 'sync_pause'});
      }
    });
  }

  // ── Broadcast helpers ─────────────────────────────────────────────────────

  void _broadcastPrepare(Song song, int posMs, {required bool autoPlay}) {
    if (state.connectedEndpoints.isEmpty) return;
    state = state.copyWith(readyEndpoints: {}, isSyncing: autoPlay);
    print('[Sync] 📤 Broadcast prepare: ${song.title} @ ${posMs}ms');
    for (final id in state.connectedEndpoints.keys) {
      _sendPrepare(id, song, posMs, autoPlay: autoPlay);
    }
  }

  void _sendPrepare(String toId, Song song, int posMs, {required bool autoPlay}) {
    _send(toId, {
      'type': 'sync_prepare',
      'positionMs': posMs,
      'autoPlay': autoPlay,
      'song': {
        'id': song.id,
        'title': song.title,
        'artist': song.artist,
        'album': song.album,
        'albumArt': song.albumArt,
        'durationMs': song.duration.inMilliseconds,
        'previewUrl': song.previewUrl,
      },
    });
  }

  void _broadcastSyncStart() {
    // Give 1200ms lead time for network latency
    final startAt = DateTime.now().millisecondsSinceEpoch + 1200;
    final pos = _ref.read(currentPositionProvider).valueOrNull ?? Duration.zero;

    print('[Sync] 🚀 Broadcasting sync_start at $startAt pos=${pos.inMilliseconds}ms');

    _broadcastAll({
      'type': 'sync_start',
      'startAt': startAt,
      'positionMs': pos.inMilliseconds,
    });

    // Host also schedules itself
    _schedulePlay(startAt, pos.inMilliseconds);
  }

  void _schedulePlay(int startAtMs, int posMs) {
    _syncTimer?.cancel();
    final delay = startAtMs - DateTime.now().millisecondsSinceEpoch;

    if (delay <= 0) {
      print('[Sync] ⚡ Instant play (${delay.abs()}ms late)');
      _suppressBroadcast = true;
      _ref.read(audioServiceProvider).seek(Duration(milliseconds: posMs)).then((_) {
        _ref.read(audioServiceProvider).play();
        _suppressBroadcast = false;
        state = state.copyWith(isSyncing: false);
      });
      return;
    }

    print('[Sync] ⏳ Scheduled play in ${delay}ms');
    _syncTimer = Timer(Duration(milliseconds: delay), () {
      _suppressBroadcast = true;
      _ref.read(audioServiceProvider).seek(Duration(milliseconds: posMs)).then((_) {
        _ref.read(audioServiceProvider).play();
        _suppressBroadcast = false;
        if (mounted) state = state.copyWith(isSyncing: false);
      });
    });
  }

  void _broadcastAll(Map<String, dynamic> data) {
    final bytes = utf8.encode(jsonEncode(data));
    for (final id in state.connectedEndpoints.keys) {
      Nearby().sendBytesPayload(id, bytes);
    }
  }

  void _send(String toId, Map<String, dynamic> data) {
    try {
      Nearby().sendBytesPayload(toId, utf8.encode(jsonEncode(data)));
    } catch (e) {
      print('[Sync] Send error to $toId: $e');
    }
  }

  // ── Permissions ───────────────────────────────────────────────────────────

  Future<void> _requestPermissions({required bool isHost}) async {
    final perms = [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ];
    if (isHost) perms.add(Permission.bluetoothAdvertise);
    await perms.request();
  }

  // ── Stop ──────────────────────────────────────────────────────────────────

  void stopSync() {
    _syncTimer?.cancel();
    _songSub?.close();
    _playingSub?.close();
    _songSub = null;
    _playingSub = null;
    try {
      Nearby().stopAdvertising();
      Nearby().stopDiscovery();
      Nearby().stopAllEndpoints();
    } catch (_) {}
    state = const SyncState();
    print('[Sync] 🛑 Stopped');
  }

  @override
  void dispose() {
    stopSync();
    super.dispose();
  }
}
