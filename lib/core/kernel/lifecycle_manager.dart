import 'package:flutter/widgets.dart';
import 'engine_coordinator.dart';

class LifecycleManager with WidgetsBindingObserver {
  static final LifecycleManager _instance = LifecycleManager._internal();
  factory LifecycleManager() => _instance;
  LifecycleManager._internal();

  bool _isInitialized = false;

  /// Starts listening to widgets app lifecycle bindings.
  void startListening() {
    if (_isInitialized) return;
    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
    debugPrint('[LifecycleManager] 📱 Started observing app lifecycle state change.');
  }

  /// Stops listening.
  void stopListening() {
    if (!_isInitialized) return;
    WidgetsBinding.instance.removeObserver(this);
    _isInitialized = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[LifecycleManager] 📱 Flutter app lifecycle changed: $state');
    
    switch (state) {
      case AppLifecycleState.resumed:
        EngineCoordinator().resume();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        EngineCoordinator().pause();
        break;
      case AppLifecycleState.detached:
        EngineCoordinator().stop();
        break;
      default:
        break;
    }
  }
}
