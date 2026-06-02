import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../domain/entities/song.dart';
import '../providers/audio_provider.dart';
import '../providers/lock_provider.dart';

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
  final Map<String, String> connectedEndpoints;
  final String? roomPassword;
  final bool isPasswordVerified;
  final bool isSyncing;
  final Map<String, bool> readyEndpoints;
  final Song? currentRoomSong;
  final Duration? currentRoomPosition;
  final int countdownSeconds; // 0 = playing, >0 = buffering countdown

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
    this.currentRoomSong,
    this.currentRoomPosition,
    this.countdownSeconds = 0,
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
    Song? currentRoomSong,
    Duration? currentRoomPosition,
    int? countdownSeconds,
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
        currentRoomSong: currentRoomSong ?? this.currentRoomSong,
        currentRoomPosition: currentRoomPosition ?? this.currentRoomPosition,
        countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      );

}

final syncProvider =
    StateNotifierProvider<SyncNotifier, SyncState>((ref) => SyncNotifier(ref));

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  final Strategy _strategy = Strategy.P2P_STAR;

  ProviderSubscription? _songSub;
  ProviderSubscription? _playingSub;
  ProviderSubscription? _positionSub;
  Timer? _syncTimer;
  Timer? _syncTimeoutTimer;

  int _networkOffset = 0;
  Timer? _clockSyncTimer;
  bool _suppressBroadcast = false;
  Timer? _countdownTimer;       // countdown before synchronized play
  
  // Smart throttling for rapid song changes
  Timer? _songChangeThrottle;
  String? _pendingSongId;
  int _lastSyncTime = 0;
  
  // Network latency compensation
  int _averageLatency = 100; // Start with 100ms estimate
  final List<int> _latencyMeasurements = [];
  
  // Track user-initiated changes for instant sync
  String? _lastSongId;
  int _lastSongChangeTime = 0;

  static const int _syncDelaySeconds = 6; // buffer window before synchronized start


  SyncNotifier(this._ref) : super(const SyncState());

  Future<void> createRoom(String password) async {
    try {
      final myName = _ref.read(lockProvider).userName ?? 'Host';
      print('[Sync] 🏠 Creating room as: $myName');
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
        print('[Sync] ✅ Room created successfully, starting host listeners...');
        _startHostListeners();
      } else {
        print('[Sync] ❌ Failed to start advertising');
        state = state.copyWith(
            status: SyncStatus.error, errorMessage: 'Failed to start advertising.');
      }
    } catch (e) {
      print('[Sync] ❌ Room creation error: $e');
      state = state.copyWith(status: SyncStatus.error, errorMessage: 'Error: $e');
    }
  }

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
  void _onConnectionInitiated(String id, ConnectionInfo info) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: _onPayloadReceived,
      onPayloadTransferUpdate: (_, __) {},
    );
  }

  void _onConnectionResult(String id, Status status) {
    print('[Sync] 🔗 Connection result for $id: $status');
    if (status == Status.CONNECTED) {
      if (!state.isHost) {
        final myName = _ref.read(lockProvider).userName ?? 'Guest';
        print('[Sync] 👤 Guest connected, sending auth...');
        _send(id, {'type': 'auth_password', 'value': state.roomPassword, 'name': myName});
        final ep = state.discoveredEndpoints.firstWhere(
          (e) => e.id == id,
          orElse: () => Endpoint(id, 'Host'),
        );
        state = state.copyWith(status: SyncStatus.joined, hostName: ep.name);
        _startClockSync();
      } else {
        print('[Sync] 🏠 Host received connection from $id');
      }
    }
  }

  void _onDisconnected(String id) {
    final newConn = Map<String, String>.from(state.connectedEndpoints)..remove(id);
    final newReady = Map<String, bool>.from(state.readyEndpoints)..remove(id);
    state = state.copyWith(
      connectedEndpoints: newConn,
      connectedUsers: newConn.values.toList(),
      readyEndpoints: newReady,
    );
    if (!state.isHost && newConn.isEmpty) stopSync();
  }

  void _onPayloadReceived(String fromId, Payload payload) async {
    if (payload.type != PayloadType.BYTES) return;
    try {
      final data = jsonDecode(utf8.decode(payload.bytes!)) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'auth_password' && state.isHost) {
        print('[Sync] 🔐 Received auth from ${data['name']}: ${data['value'] == state.roomPassword ? 'VALID' : 'INVALID'}');
        if (data['value'] == state.roomPassword) {
          final newConn = Map<String, String>.from(state.connectedEndpoints)
            ..[fromId] = data['name'] as String? ?? 'Friend';
          state = state.copyWith(
            connectedEndpoints: newConn,
            connectedUsers: newConn.values.toList(),
          );
          print('[Sync] ✅ User ${data['name']} authenticated. Connected users: ${newConn.length}');
          _send(fromId, {'type': 'auth_ok'});
          
          // FIRST CONNECTION SYNC - Sync to current host position
          print('[Sync] 🚀 First connection sync to current position...');
          _forceImmediateSync(fromId);
          
        } else {
          print('[Sync] ❌ Invalid password from ${data['name']}, disconnecting');
          Nearby().disconnectFromEndpoint(fromId);
        }
        return;
      }

      if (type == 'auth_ok') {
        state = state.copyWith(isPasswordVerified: true);
        return;
      }

      if (!state.isPasswordVerified && !state.isHost) return;
      if (type == 'clock_sync_request') {
        final clientTime = data['clientTime'] as int;
        final serverTime = _getNetworkTime();
        _send(fromId, {
          'type': 'clock_sync_response',
          'clientTime': clientTime,
          'serverTime': serverTime,
        });
        return;
      }

      if (type == 'clock_sync_response') {
        final clientTime = data['clientTime'] as int;
        final serverTime = data['serverTime'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        final rtt = now - clientTime;
        final offset = serverTime - clientTime - (rtt ~/ 2);
        _networkOffset = offset;
        
        // Measure and track latency for predictive sync
        _latencyMeasurements.add(rtt);
        if (_latencyMeasurements.length > 10) {
          _latencyMeasurements.removeAt(0); // Keep only last 10 measurements
        }
        _averageLatency = _latencyMeasurements.reduce((a, b) => a + b) ~/ _latencyMeasurements.length;
        print('[Sync] 📊 RTT: ${rtt}ms, Average latency: ${_averageLatency}ms');
        return;
      }

      // COUNTDOWN NEW SONG SYNC
      // ─────────────────────────────────────────────────────────────────────
      // 1. Host sends song data + an absolute epoch timestamp 6s in the future.
      // 2. All clients receive this and IMMEDIATELY start buffering/loading.
      // 3. Every device waits until the epoch timestamp is reached, then plays.
      // This gives all devices 5-6s to pre-buffer regardless of connection speed.
      if (type == 'sync_countdown_new_song') {
        final songData = data['song'] as Map<String, dynamic>;
        final playAtEpoch = data['playAtEpoch'] as int; // absolute epoch ms

        print('[Sync] ⏳ COUNTDOWN SYNC: "${songData['title']}" — loading now, play at epoch $playAtEpoch');

        _suppressBroadcast = true;
        _countdownTimer?.cancel();

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

          final audio = _ref.read(audioServiceProvider);

          // Step 1: load and immediately PAUSE (buffer without playing)
          await audio.loadQueueInstant([song], startIndex: 0, seekTo: Duration.zero);
          print('[Sync] 📦 Song buffered. Waiting for countdown...');

          // Step 2: countdown to the agreed epoch
          final now = DateTime.now().millisecondsSinceEpoch + _networkOffset;
          final waitMs = playAtEpoch - now;

          if (waitMs > 0) {
            _countdownTimer = Timer(Duration(milliseconds: waitMs), () async {
              await audio.play();
              _suppressBroadcast = false;
              print('[Sync] 🚀 SYNCHRONIZED START — all devices playing now!');
            });
          } else {
            // Already past the epoch (very slow network) — start immediately
            await audio.play();
            _suppressBroadcast = false;
            print('[Sync] ⚡ Late start — playing immediately (was ${-waitMs}ms late)');
          }
        } catch (e) {
          _suppressBroadcast = false;
          print('[Sync] ❌ Countdown sync error: $e');
        }
        return;
      }

      // INSTANT FIRST CONNECTION SYNC - Zero delay, immediate sync to position
      if (type == 'sync_instant_first_connection') {
        final songData = data['song'] as Map<String, dynamic>;
        final posMs = data['positionMs'] as int;
        final isPlaying = data['isPlaying'] as bool;
        
        print('[Sync] 🔗 INSTANT FIRST CONNECTION: "${songData['title']}" at ${posMs}ms - ZERO DELAY');
        
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
          
          final audio = _ref.read(audioServiceProvider);
          final targetPosition = Duration(milliseconds: posMs.clamp(0, song.duration.inMilliseconds));
          
          // INSTANT loading at position - NO DELAYS
          await audio.loadQueueInstant([song], startIndex: 0, seekTo: targetPosition);
          
          if (isPlaying) {
            await audio.play();
            print('[Sync] ⚡ INSTANT FIRST CONNECTION started at ${targetPosition.inSeconds}s');
          } else {
            print('[Sync] ⏸️ INSTANT FIRST CONNECTION loaded paused at ${targetPosition.inSeconds}s');
          }
          
        } catch (e) {
          print('[Sync] ❌ Instant first connection sync error: $e');
        } finally {
          _suppressBroadcast = false;
        }
        return;
      }

      // INSTANT PLAY SYNC - Zero delay, immediate play at position
      if (type == 'sync_instant_play') {
        final posMs = data['positionMs'] as int;
        
        _suppressBroadcast = true;
        
        // INSTANT seek and play - NO DELAYS
        final targetPos = Duration(milliseconds: posMs);
        await _ref.read(audioServiceProvider).seek(targetPos);
        await _ref.read(audioServiceProvider).play();
        
        _suppressBroadcast = false;
        print('[Sync] ⚡ INSTANT PLAY executed at ${targetPos.inSeconds}s');
        return;
      }

      if (type == 'sync_pause') {
        _suppressBroadcast = true;
        _ref.read(audioServiceProvider).pause();
        _suppressBroadcast = false;
        return;
      }

      if (type == 'sync_seek') {
        final posMs = data['positionMs'] as int;
        
        _suppressBroadcast = true;
        
        final targetPos = Duration(milliseconds: posMs.clamp(0, 300000));
        await _ref.read(audioServiceProvider).seek(targetPos);
        _suppressBroadcast = false;
        print('[Sync] ⏭️ Seek executed to ${targetPos.inSeconds}s');
        return;
      }

    } catch (e) {
      // Ignore payload errors
    }
  }
  void _startHostListeners() {
    print('[Sync] 🎙️ Starting host listeners...');

    _songSub = _ref.listen<AsyncValue<Song?>>(currentSongProvider, (prev, next) {
      if (_suppressBroadcast) {
        print('[Sync] 🔇 Song change suppressed (broadcast blocked)');
        return;
      }
      final song = next.valueOrNull;
      if (song == null) {
        print('[Sync] ⚠️ No current song available');
        return;
      }
      if (!state.isHost) {
        print('[Sync] ⚠️ Not host, ignoring song change');
        return;
      }
      if (state.connectedEndpoints.isEmpty) {
        print('[Sync] ⚠️ No connected endpoints, ignoring song change');
        return;
      }
      if (song.id == _lastSongId) {
        print('[Sync] ⚠️ Same song, ignoring change');
        return;
      }
      
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSinceLastChange = now - _lastSongChangeTime;
      
      _lastSongId = song.id;
      _lastSongChangeTime = now;
      _pendingSongId = song.id;
      
      // INSTANT SYNC for user-initiated changes (next/previous buttons)
      // Throttle only for rapid automated changes (< 500ms apart)
      if (timeSinceLastChange > 500) {
        // User-initiated change - INSTANT SYNC
        print('[Sync] 🎵 INSTANT USER SONG CHANGE: "${song.title}" - ZERO DELAY from 0:00');
        _forceNewSongSync();
        _lastSyncTime = now;
      } else {
        // Rapid change - use throttling to prevent spam
        print('[Sync] 🔄 Rapid song change detected - throttling');
        _songChangeThrottle?.cancel();
        _songChangeThrottle = Timer(const Duration(milliseconds: 50), () {
          if (_pendingSongId == song.id && state.isHost && state.connectedEndpoints.isNotEmpty) {
            print('[Sync] 🎵 THROTTLED SONG CHANGE: "${song.title}" - from 0:00');
            _forceNewSongSync();
            _lastSyncTime = DateTime.now().millisecondsSinceEpoch;
          }
        });
      }
    });

    _playingSub = _ref.listen<AsyncValue<bool>>(isPlayingProvider, (prev, next) {
      if (_suppressBroadcast) {
        print('[Sync] 🔇 Play/pause suppressed (broadcast blocked)');
        return;
      }
      if (!state.isHost) {
        print('[Sync] ⚠️ Not host, ignoring play/pause');
        return;
      }
      if (state.connectedEndpoints.isEmpty) {
        print('[Sync] ⚠️ No connected endpoints, ignoring play/pause');
        return;
      }
      final isPlaying = next.valueOrNull ?? false;
      final wasPlaying = prev?.valueOrNull ?? false;
      if (isPlaying == wasPlaying) {
        print('[Sync] ⚠️ Same playing state, ignoring');
        return;
      }

      print('[Sync] ${isPlaying ? '▶️' : '⏸️'} Host ${isPlaying ? 'play' : 'pause'} - syncing to ${state.connectedEndpoints.length} devices');
      
      if (isPlaying) {
        // INSTANT PLAY SYNC - Zero countdown, immediate execution
        final currentPos = _ref.read(currentPositionProvider).valueOrNull ?? Duration.zero;
        
        _broadcastAll({
          'type': 'sync_instant_play',
          'positionMs': currentPos.inMilliseconds,
        });
      } else {
        _broadcastAll({'type': 'sync_pause'});
      }
    });

    _positionSub = _ref.listen<AsyncValue<Duration>>(currentPositionProvider, (prev, next) {
      if (_suppressBroadcast) return;
      if (!state.isHost || state.connectedEndpoints.isEmpty) return;
      
      final currentPos = next.valueOrNull ?? Duration.zero;
      final prevPos = prev?.valueOrNull ?? Duration.zero;
      
      // Ignore position jumps if we just changed songs or are near the start/end
      if (currentPos.inMilliseconds < 2000) return;
      
      final timeDiff = (currentPos - prevPos).abs();
      // Only broadcast seek if it's a real user seek (> 2 seconds difference)
      if (timeDiff > const Duration(milliseconds: 2000)) {
        print('[Sync] ⏭️ Host seek: ${currentPos.inSeconds}s - syncing to ${state.connectedEndpoints.length} devices');
        _broadcastAll({
          'type': 'sync_seek',
          'positionMs': currentPos.inMilliseconds,
        });
      }
    });
    
    print('[Sync] ✅ Host listeners started successfully');
  }

  void _forceImmediateSyncAll() {
    if (!state.isHost || state.connectedEndpoints.isEmpty) return;
    print('[Sync] 🔄 Force syncing to all ${state.connectedEndpoints.length} devices');
    for (final id in state.connectedEndpoints.keys) {
      _forceImmediateSync(id);
    }
  }

  /// COUNTDOWN NEW SONG SYNC — 5s buffer window before synchronized start.
  ///
  /// Flow:
  ///   1. Host calculates epoch = now + 6s
  ///   2. Broadcasts song data + epoch to all clients
  ///   3. Clients buffer immediately, then play exactly at epoch
  ///   4. Result: all devices start within milliseconds of each other
  void _forceNewSongSync() {
    final song = _ref.read(currentSongProvider).valueOrNull;
    final isPlaying = _ref.read(isPlayingProvider).valueOrNull ?? false;

    if (song == null) return;

    _countdownTimer?.cancel();

    // Schedule play 6 seconds from now — gives all devices time to buffer
    final playAtEpoch = _getNetworkTime() + (_syncDelaySeconds * 1000);

    print('[Sync] 📡 COUNTDOWN BROADCAST: "${song.title}" — play at epoch $playAtEpoch (${_syncDelaySeconds}s from now)');
    print('[Sync] ⏳ Host showing 5-second countdown...');

    _broadcastAll({
      'type': 'sync_countdown_new_song',
      'isPlaying': isPlaying,
      'playAtEpoch': playAtEpoch,
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

    // Host also waits for the same epoch before playing
    if (isPlaying) {
      final now = _getNetworkTime();
      final waitMs = playAtEpoch - now;
      
      _suppressBroadcast = true;
      _ref.read(audioServiceProvider).pause(); // pause during countdown
      // We keep suppressBroadcast true briefly to ensure no spurious play state changes are broadcast
      Future.delayed(const Duration(milliseconds: 500), () {
        _suppressBroadcast = false;
      });

      _countdownTimer = Timer(Duration(milliseconds: waitMs), () {
        _suppressBroadcast = true;
        _ref.read(audioServiceProvider).play();
        _suppressBroadcast = false;
        print('[Sync] 🚀 HOST SYNCHRONIZED START');
      });
    }
  }


  /// INSTANT FIRST CONNECTION SYNC - Zero countdown, immediate sync to position
  void _forceImmediateSync(String toId) {
    final song = _ref.read(currentSongProvider).valueOrNull;
    final pos = _ref.read(currentPositionProvider).valueOrNull ?? Duration.zero;
    final isPlaying = _ref.read(isPlayingProvider).valueOrNull ?? false;
    
    if (song != null) {
      print('[Sync] 📤 INSTANT FIRST CONNECTION to $toId: "${song.title}" at ${pos.inSeconds}s - ZERO DELAY');
      _send(toId, {
        'type': 'sync_instant_first_connection',
        'positionMs': pos.inMilliseconds,
        'isPlaying': isPlaying,
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
    } else {
      print('[Sync] ⚠️ Cannot sync - no current song available');
    }
  }
  
  void _broadcastAll(Map<String, dynamic> data) {
    print('[Sync] 📡 Broadcasting ${data['type']} to ${state.connectedEndpoints.length} devices');
    final bytes = utf8.encode(jsonEncode(data));
    for (final id in state.connectedEndpoints.keys) {
      Nearby().sendBytesPayload(id, bytes);
    }
  }

  void _send(String toId, Map<String, dynamic> data) {
    try {
      Nearby().sendBytesPayload(toId, utf8.encode(jsonEncode(data)));
    } catch (e) {
      // Ignore send errors
    }
  }

  void _startClockSync() {
    if (state.isHost || state.connectedEndpoints.isEmpty) return;
    
    _clockSyncTimer?.cancel();
    _clockSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.isActive || state.connectedEndpoints.isEmpty) return;
      
      final hostId = state.connectedEndpoints.keys.first;
      final clientTime = DateTime.now().millisecondsSinceEpoch;
      _send(hostId, {
        'type': 'clock_sync_request',
        'clientTime': clientTime,
      });
    });
  }

  int _getNetworkTime() {
    return DateTime.now().millisecondsSinceEpoch + _networkOffset;
  }

  void clearSyncState() {
    _syncTimer?.cancel();
    _syncTimeoutTimer?.cancel();
    state = state.copyWith(isSyncing: false, readyEndpoints: {});
  }

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

  void stopSync() {
    _syncTimer?.cancel();
    _syncTimeoutTimer?.cancel();
    _clockSyncTimer?.cancel();
    _songChangeThrottle?.cancel();
    _countdownTimer?.cancel();
    _songSub?.close();
    _playingSub?.close();
    _positionSub?.close();
    _songSub = null;
    _playingSub = null;
    _positionSub = null;
    _clockSyncTimer = null;
    _songChangeThrottle = null;
    _countdownTimer = null;
    _networkOffset = 0;
    _lastSyncTime = 0;
    _pendingSongId = null;
    _lastSongId = null;
    _lastSongChangeTime = 0;
    try {
      Nearby().stopAdvertising();
      Nearby().stopDiscovery();
      Nearby().stopAllEndpoints();
    } catch (_) {}
    state = const SyncState();
  }


  @override
  void dispose() {
    stopSync();
    super.dispose();
  }
}