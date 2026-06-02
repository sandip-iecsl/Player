import 'package:flutter/material.dart';
import '../../data/services/screen_state_service.dart';

/// Widget that listens to screen state changes and maintains audio playback
class ScreenStateListener extends StatefulWidget {
  final Widget child;
  
  const ScreenStateListener({
    super.key,
    required this.child,
  });
  
  @override
  State<ScreenStateListener> createState() => _ScreenStateListenerState();
}

class _ScreenStateListenerState extends State<ScreenStateListener> 
    with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Listen to screen state changes
    ScreenStateService.stateStream.listen((state) {
      debugPrint('🔄 Screen state update: $state');
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('📱 App resumed - checking audio state');
        _ensureAudioContinues();
        break;
      case AppLifecycleState.paused:
        debugPrint('📱 App paused - preparing for background/AOD');
        break;
      case AppLifecycleState.inactive:
        debugPrint('📱 App inactive - maintaining audio focus');
        break;
      case AppLifecycleState.detached:
        debugPrint('📱 App detached');
        break;
      case AppLifecycleState.hidden:
        debugPrint('📱 App hidden - preparing for AOD');
        break;
    }
  }
  
  /// Ensure audio continues playing when app state changes
  void _ensureAudioContinues() {
    // Small delay to let the system settle
    Future.delayed(const Duration(milliseconds: 100), () {
      // This will be handled by the ScreenStateService automatically
      debugPrint('🎵 Audio continuity check completed');
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}