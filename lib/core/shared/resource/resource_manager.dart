import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../kernel/i_engine.dart';
import '../scheduler/scheduler_engine.dart';
import '../../cache/cache_eviction_engine.dart';
import '../error/error_manager.dart';

class ResourceManager implements IEngine {
  static final ResourceManager _instance = ResourceManager._internal();
  factory ResourceManager() => _instance;
  ResourceManager._internal();

  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  bool _isLowPowerMode = false;

  @override
  Future<void> initialize() async {
    debugPrint('[ResourceManager] 🔋 Initialized.');
  }

  @override
  Future<void> start() async {
    // 1. Listen to connectivity updates
    _networkSubscription = Connectivity().onConnectivityChanged.listen((results) {
      _evaluateResources();
    });

    // 2. Schedule a resource scan task through SchedulerEngine every 60 seconds
    SchedulerEngine().scheduleTask('resource_scan', const Duration(seconds: 60), () {
      _performPeriodicResourceScan();
    });
  }

  /// Triggers local metrics verification.
  Future<void> _performPeriodicResourceScan() async {
    try {
      // Perform local cache cleanup if sizes exceed limits
      await CacheEvictionEngine().runEviction();
      _evaluateResources();
    } catch (e, stack) {
      ErrorManager().captureError(e, stack, context: 'ResourceManager.resourceScan');
    }
  }

  void _evaluateResources() {
    // Evaluate power/connectivity to alter task priorities or intervals
    debugPrint('[ResourceManager] 🔋 Evaluating device resources...');
  }

  /// Exposes current power saving toggle status.
  bool get isLowPowerMode => _isLowPowerMode;

  /// Sets power saving mode manually (can be driven by settings).
  void setLowPowerMode(bool enabled) {
    _isLowPowerMode = enabled;
    debugPrint('[ResourceManager] 🔋 Power Saver Toggle: $enabled');
    _evaluateResources();
  }

  @override
  Future<void> pause() async {
    _networkSubscription?.pause();
  }

  @override
  Future<void> resume() async {
    _networkSubscription?.resume();
  }

  @override
  Future<void> stop() async {
    _networkSubscription?.cancel();
    SchedulerEngine().unscheduleTask('resource_scan');
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
