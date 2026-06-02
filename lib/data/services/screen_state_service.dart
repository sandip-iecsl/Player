import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'audio_service.dart' show audioHandler, AudioServiceHandler;
import 'always_on_display_service.dart';

/// Service to monitor screen state changes and coordinate with audio playback
class ScreenStateService {
  static const MethodChannel _channel = MethodChannel('aura_player/screen_state');
  
  static bool _isInitialized = false;
  static bool _isScreenOn = true;
  static bool _isAODActive = false;
  static StreamController<ScreenState>? _stateController;
  
  /// Stream to monitor screen state changes
  static Stream<ScreenState> get stateStream {
    _stateController ??= StreamController<ScreenState>.broadcast();
    return _stateController!.stream;
  }
  
  /// Initialize screen state monitoring
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Set up method channel handler for native callbacks
      _channel.setMethodCallHandler(_handleMethodCall);
      
      // Register for screen state changes
      await _channel.invokeMethod('registerScreenStateListener');
      
      _isInitialized = true;
      debugPrint('✅ Screen state service initialized');
    } on MissingPluginException {
      debugPrint('ℹ️ Screen state plugin not implemented on this platform');
    } catch (e) {
      debugPrint('❌ Failed to initialize screen state service: $e');
    }
  }
  
  /// Handle method calls from native platform
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onScreenStateChanged':
        await _handleScreenStateChange(call.arguments);
        break;
      case 'onAODStateChanged':
        await _handleAODStateChange(call.arguments);
        break;
      default:
        debugPrint('Unknown method call: ${call.method}');
    }
  }
  
  /// Handle screen on/off state changes
  static Future<void> _handleScreenStateChange(dynamic arguments) async {
    try {
      final isScreenOn = arguments['isScreenOn'] as bool? ?? true;
      final wasScreenOn = _isScreenOn;
      _isScreenOn = isScreenOn;
      
      debugPrint('📱 Screen state changed: $wasScreenOn → $isScreenOn');
      
      // Emit state change
      _stateController?.add(ScreenState(
        isScreenOn: isScreenOn,
        isAODActive: _isAODActive,
        timestamp: DateTime.now(),
      ));
      
      // Coordinate with audio service to maintain playback
      if (audioHandler is AudioServiceHandler) {
        final handler = audioHandler as AudioServiceHandler;
        await handler.handleScreenStateChange(
          isScreenOn: isScreenOn,
          isAODActive: _isAODActive,
        );
      }
      
      // If screen is turning off and music is playing, prepare for AOD
      if (!isScreenOn && audioHandler.playbackState.value.playing) {
        debugPrint('🎵 Screen off with music playing - preparing for AOD');
        await _prepareForAOD();
      }
    } catch (e) {
      debugPrint('❌ Error handling screen state change: $e');
    }
  }
  
  /// Handle always-on display state changes
  static Future<void> _handleAODStateChange(dynamic arguments) async {
    try {
      final isAODActive = arguments['isAODActive'] as bool? ?? false;
      final wasAODActive = _isAODActive;
      _isAODActive = isAODActive;
      
      debugPrint('🌙 AOD state changed: $wasAODActive → $isAODActive');
      
      // Emit state change
      _stateController?.add(ScreenState(
        isScreenOn: _isScreenOn,
        isAODActive: isAODActive,
        timestamp: DateTime.now(),
      ));
      
      // Coordinate with audio service
      if (audioHandler is AudioServiceHandler) {
        final handler = audioHandler as AudioServiceHandler;
        await handler.handleScreenStateChange(
          isScreenOn: _isScreenOn,
          isAODActive: isAODActive,
        );
      }
      
      // Handle AOD activation/deactivation
      if (isAODActive && !wasAODActive) {
        await _onAODActivated();
      } else if (!isAODActive && wasAODActive) {
        await _onAODDeactivated();
      }
    } catch (e) {
      debugPrint('❌ Error handling AOD state change: $e');
    }
  }
  
  /// Prepare for always-on display activation
  static Future<void> _prepareForAOD() async {
    try {
      // Ensure audio focus is maintained
      if (audioHandler is AudioServiceHandler) {
        final handler = audioHandler as AudioServiceHandler;
        await handler.maintainAudioFocus();
      }
      
      // Pre-configure AOD settings
      await AlwaysOnDisplayService.enableMusicControlsOnAOD();
    } catch (e) {
      debugPrint('❌ Error preparing for AOD: $e');
    }
  }
  
  /// Handle AOD activation
  static Future<void> _onAODActivated() async {
    try {
      debugPrint('🌙 AOD activated - ensuring music continues');
      
      // Ensure music controls are enabled on AOD
      await AlwaysOnDisplayService.enableMusicControlsOnAOD();
      
      // Maintain audio focus
      if (audioHandler is AudioServiceHandler) {
        final handler = audioHandler as AudioServiceHandler;
        await handler.maintainAudioFocus();
      }
    } catch (e) {
      debugPrint('❌ Error handling AOD activation: $e');
    }
  }
  
  /// Handle AOD deactivation
  static Future<void> _onAODDeactivated() async {
    try {
      debugPrint('🌅 AOD deactivated - maintaining music playback');
      
      // Ensure audio continues after AOD
      if (audioHandler is AudioServiceHandler) {
        final handler = audioHandler as AudioServiceHandler;
        await handler.maintainAudioFocus();
      }
    } catch (e) {
      debugPrint('❌ Error handling AOD deactivation: $e');
    }
  }
  
  /// Get current screen state
  static ScreenState get currentState => ScreenState(
    isScreenOn: _isScreenOn,
    isAODActive: _isAODActive,
    timestamp: DateTime.now(),
  );
  
  /// Dispose resources
  static void dispose() {
    _stateController?.close();
    _stateController = null;
    _isInitialized = false;
  }
}

/// Represents the current screen state
class ScreenState {
  final bool isScreenOn;
  final bool isAODActive;
  final DateTime timestamp;
  
  const ScreenState({
    required this.isScreenOn,
    required this.isAODActive,
    required this.timestamp,
  });
  
  @override
  String toString() => 'ScreenState(screenOn: $isScreenOn, AOD: $isAODActive)';
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenState &&
          runtimeType == other.runtimeType &&
          isScreenOn == other.isScreenOn &&
          isAODActive == other.isAODActive;
  
  @override
  int get hashCode => isScreenOn.hashCode ^ isAODActive.hashCode;
}