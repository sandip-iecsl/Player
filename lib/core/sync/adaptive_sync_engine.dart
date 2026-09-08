import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../commands/app_command.dart';
import '../commands/app_command_factory.dart';
import '../events/event_dispatcher.dart';
import '../events/admin_events.dart';
import '../../core/security/encryption_helper.dart';

import '../kernel/i_engine.dart';

class AdaptiveSyncEngine with WidgetsBindingObserver implements IEngine {
  static final AdaptiveSyncEngine _instance = AdaptiveSyncEngine._internal();
  factory AdaptiveSyncEngine() => _instance;
  AdaptiveSyncEngine._internal();

  Box<String>? _commandQueueBox;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _isInBackground = false;
  bool _isBatterySaverEnabled = false; // Can be toggled manually or set via logic
  bool _isCharging = false;            // Can be toggled or set via simulated states

  ConnectivityResult _currentConnectivity = ConnectivityResult.none;

  @override
  Future<void> initialize() async {
    try {
      final cipher = await EncryptionHelper.getHiveCipher();
      _commandQueueBox = await Hive.openBox<String>(
        'command_sync_queue',
        encryptionCipher: cipher,
      );

      // Register lifecycle observer
      WidgetsBinding.instance.addObserver(this);

      // Observe connectivity
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
        _currentConnectivity = results.isNotEmpty ? results.first : ConnectivityResult.none;
        _evaluateSyncInterval();
      });

      // Fetch initial connectivity
      final initConnectivity = await Connectivity().checkConnectivity();
      _currentConnectivity = initConnectivity.isNotEmpty ? initConnectivity.first : ConnectivityResult.none;

      debugPrint('[AdaptiveSyncEngine] 🔄 Initialized.');
      _evaluateSyncInterval();
      
      // Trigger initial sync for any leftover queue
      forceSync();
    } catch (e) {
      debugPrint('[AdaptiveSyncEngine] ⚠️ Initialization failed: $e');
    }
  }

  /// Add command to queue and evaluate synchronization scheduling.
  Future<void> enqueue(AppCommand command) async {
    if (_commandQueueBox == null) return;

    // Use commandId as key
    await _commandQueueBox!.put(command.commandId, jsonEncode(command.toJson()));
    debugPrint('[AdaptiveSyncEngine] 📥 Command enqueued: ${command.type} (${command.commandId})');

    // If critical/immediate, sync instantly
    if (command.priority == CommandPriority.critical) {
      forceSync();
    } else {
      _evaluateSyncInterval();
    }
  }

  /// Sets battery saver status manually.
  void setBatterySaver(bool enabled) {
    if (_isBatterySaverEnabled != enabled) {
      _isBatterySaverEnabled = enabled;
      debugPrint('[AdaptiveSyncEngine] 🔋 Battery Saver: $enabled');
      _evaluateSyncInterval();
    }
  }

  /// Sets charging status manually.
  void setCharging(bool charging) {
    if (_isCharging != charging) {
      _isCharging = charging;
      debugPrint('[AdaptiveSyncEngine] ⚡ Charging state: $charging');
      _evaluateSyncInterval();
    }
  }

  /// Dynamically computes and schedules sync interval based on device & app state.
  void _evaluateSyncInterval() {
    _syncTimer?.cancel();

    if (_isInBackground) {
      debugPrint('[AdaptiveSyncEngine] 💤 App in background. Sync paused.');
      return;
    }

    if (_currentConnectivity == ConnectivityResult.none) {
      debugPrint('[AdaptiveSyncEngine] 🛜 Offline. Sync paused (waiting for connection).');
      return;
    }

    int intervalSeconds = 20; // Default Foreground

    if (_isCharging) {
      intervalSeconds = 10;
    } else if (_isBatterySaverEnabled) {
      intervalSeconds = 90;
    } else if (_currentConnectivity == ConnectivityResult.wifi) {
      intervalSeconds = 15;
    } else if (_currentConnectivity == ConnectivityResult.mobile) {
      intervalSeconds = 45;
    }

    debugPrint('[AdaptiveSyncEngine] 🕒 Sync interval set to $intervalSeconds seconds.');
    _syncTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) => forceSync());
  }

  /// Force run a synchronization cycle immediately.
  Future<void> forceSync() async {
    if (_isSyncing || _commandQueueBox == null || _commandQueueBox!.isEmpty) return;

    if (_currentConnectivity == ConnectivityResult.none) {
      return;
    }

    _isSyncing = true;
    debugPrint('[AdaptiveSyncEngine] 🚀 Executing queued commands...');

    try {
      final keys = _commandQueueBox!.keys.toList();
      int successCount = 0;

      // Execute commands sequentially to preserve order
      for (final key in keys) {
        final cmdJson = _commandQueueBox!.get(key);
        if (cmdJson == null) continue;

        AppCommand command;
        try {
          final decoded = jsonDecode(cmdJson);
          command = AppCommandFactory.fromJson(decoded);
        } catch (e) {
          debugPrint('[AdaptiveSyncEngine] ⚠️ Failed parsing command $key: $e');
          await _commandQueueBox!.delete(key);
          continue;
        }

        command.status = CommandStatus.executing;
        await _commandQueueBox!.put(key, jsonEncode(command.toJson()));

        final bool success = await command.execute();

        if (success) {
          await _commandQueueBox!.delete(key);
          successCount++;
        } else {
          command.retryCount++;
          if (command.retryCount >= 5) {
            command.status = CommandStatus.failed;
            debugPrint('[AdaptiveSyncEngine] ❌ Command ${command.commandId} failed after max retries. Removing.');
            await _commandQueueBox!.delete(key);
            
            EventDispatcher().publish(QueueFailedEvent(
              eventId: 'fail_${DateTime.now().millisecondsSinceEpoch}',
              timestamp: DateTime.now(),
              error: 'Command ${command.type} failed execution.',
            ));
          } else {
            command.status = CommandStatus.pending;
            await _commandQueueBox!.put(key, jsonEncode(command.toJson()));
            debugPrint('[AdaptiveSyncEngine] ⚠️ Command ${command.commandId} failed. Retry: ${command.retryCount}');
            break; // Pause remaining queue execution until next cycle
          }
        }
      }

      if (successCount > 0) {
        EventDispatcher().publish(SyncCompletedEvent(
          eventId: 'sync_${DateTime.now().millisecondsSinceEpoch}',
          timestamp: DateTime.now(),
          count: successCount,
        ));
      }
    } catch (e) {
      debugPrint('[AdaptiveSyncEngine] ❌ Sync execution error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInBackground = (state == AppLifecycleState.paused || state == AppLifecycleState.detached);
    debugPrint('[AdaptiveSyncEngine] 📱 App lifecycle state changed: $state');
    _evaluateSyncInterval();
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> pause() async {
    _isInBackground = true;
    _evaluateSyncInterval();
  }

  @override
  Future<void> resume() async {
    _isInBackground = false;
    _evaluateSyncInterval();
  }

  @override
  Future<void> stop() async {
    _syncTimer?.cancel();
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
  }
}
