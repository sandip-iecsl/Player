import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:torch_light/torch_light.dart';

class TorchState {
  final bool isActive;        // torch is ON
  final bool isTorchOn;       // physical torch hardware state
  final bool isAvailable;
  final bool isBeatSync;      // beat-synchronized flashing mode
  final bool isUserEnabled;   // whether user explicitly enabled torch
  final double beatIntensity; // current beat intensity (0-1)

  TorchState({
    this.isActive = false,
    this.isTorchOn = false,
    this.isAvailable = false,
    this.isBeatSync = false,
    this.isUserEnabled = false,
    this.beatIntensity = 0.0,
  });

  TorchState copyWith({
    bool? isActive,
    bool? isTorchOn,
    bool? isAvailable,
    bool? isBeatSync,
    bool? isUserEnabled,
    double? beatIntensity,
  }) =>
      TorchState(
        isActive: isActive ?? this.isActive,
        isTorchOn: isTorchOn ?? this.isTorchOn,
        isAvailable: isAvailable ?? this.isAvailable,
        isBeatSync: isBeatSync ?? this.isBeatSync,
        isUserEnabled: isUserEnabled ?? this.isUserEnabled,
        beatIntensity: beatIntensity ?? this.beatIntensity,
      );
}

final torchProvider = StateNotifierProvider<TorchNotifier, TorchState>(
  (ref) => TorchNotifier(),
);

class TorchNotifier extends StateNotifier<TorchState> {
  Timer? _beatFlashTimer;

  TorchNotifier() : super(TorchState()) {
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    try {
      final available = await TorchLight.isTorchAvailable();
      state = state.copyWith(isAvailable: available);
    } catch (_) {
      state = state.copyWith(isAvailable: false);
    }
  }

  /// Toggle torch on/off in steady mode (normal torch behavior)
  Future<void> toggleActive() async {
    if (!state.isAvailable) return;
    final turningOn = !state.isActive;
    try {
      if (turningOn) {
        // Enable steady torch (not beat sync)
        await TorchLight.enableTorch();
        state = state.copyWith(isActive: true, isTorchOn: true, isBeatSync: false, isUserEnabled: true);
      } else {
        await TorchLight.disableTorch();
        _cancelBeatFlash();
        state = state.copyWith(isActive: false, isTorchOn: false, isBeatSync: false, isUserEnabled: false);
      }
    } catch (e) {
      print('[Torch] Toggle error: $e');
      state = state.copyWith(isActive: false, isTorchOn: false, isBeatSync: false, isUserEnabled: false);
    }
  }

  /// Activate beat-synchronized flashing (called from visualizer)
  Future<void> activateBeatSync() async {
    try {
      // Try to enable torch hardware — if unavailable, still set flags for UI
      if (state.isAvailable) {
        await TorchLight.enableTorch();
      }
      state = state.copyWith(
        isBeatSync: true,
        isActive: true,
        isTorchOn: state.isAvailable,
        isUserEnabled: true, // user explicitly tapped Beat
      );
    } catch (e) {
      // Even if hardware fails, enable beat-sync UI mode
      state = state.copyWith(
        isBeatSync: true,
        isActive: true,
        isUserEnabled: true,
      );
    }
  }

  /// Deactivate beat sync
  Future<void> deactivateBeatSync() async {
    _cancelBeatFlash();
    try {
      await TorchLight.disableTorch();
    } catch (_) {}
    state = state.copyWith(
      isBeatSync: false,
      isTorchOn: false,
      isActive: false,
      isUserEnabled: false,
    );
  }

  double _lastIntensity = 0.0;
  bool _isCoolingDown = false;

  /// Called by the visualizer beat timer to handle beat-sync flashing.
  /// Only perform hardware flashes when the user has explicitly enabled
  /// the torch (`isUserEnabled == true`) and beat-sync mode is active.
  Future<void> onBeat(double intensity) async {
    if (!state.isBeatSync || _isCoolingDown) return;
    if (!state.isUserEnabled) return;

    final wasBelowThreshold = _lastIntensity <= 0.35;
    final isAboveThreshold = intensity > 0.35;
    final isRising = intensity > _lastIntensity;

    state = state.copyWith(beatIntensity: intensity);

    // Only flash hardware torch if available
    if (state.isAvailable && wasBelowThreshold && isAboveThreshold && isRising) {
      try {
        _isCoolingDown = true;
        await TorchLight.enableTorch();
        state = state.copyWith(isTorchOn: true);

        final flashDuration = Duration(milliseconds: (40 + (intensity * 80)).toInt());

        _beatFlashTimer?.cancel();
        _beatFlashTimer = Timer(flashDuration, () async {
          try {
            await TorchLight.disableTorch();
            state = state.copyWith(isTorchOn: false);
            await Future.delayed(const Duration(milliseconds: 30));
            _isCoolingDown = false;
          } catch (e) {
            _isCoolingDown = false;
          }
        });
      } catch (e) {
        _isCoolingDown = false;
      }
    } else if (!state.isAvailable) {
      // No torch hardware — just update beat intensity for UI effects
      _isCoolingDown = false;
    }

    _lastIntensity = intensity;
  }

  void _cancelBeatFlash() {
    _beatFlashTimer?.cancel();
    _beatFlashTimer = null;
  }
}
