import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

/// Settings for the enhanced notification controller
class NotificationControllerSettings {
  final bool useEnhancedController;
  final bool enableBeatResponse;
  final bool enableAlwaysOnDisplay;
  final bool enableAnimations;
  final NotificationStyle style;
  final double animationIntensity;
  final Color? customAccentColor;

  const NotificationControllerSettings({
    this.useEnhancedController = true,
    this.enableBeatResponse = true,
    this.enableAlwaysOnDisplay = true,
    this.enableAnimations = true,
    this.style = NotificationStyle.enhanced,
    this.animationIntensity = 0.8,
    this.customAccentColor,
  });

  NotificationControllerSettings copyWith({
    bool? useEnhancedController,
    bool? enableBeatResponse,
    bool? enableAlwaysOnDisplay,
    bool? enableAnimations,
    NotificationStyle? style,
    double? animationIntensity,
    Color? customAccentColor,
  }) {
    return NotificationControllerSettings(
      useEnhancedController: useEnhancedController ?? this.useEnhancedController,
      enableBeatResponse: enableBeatResponse ?? this.enableBeatResponse,
      enableAlwaysOnDisplay: enableAlwaysOnDisplay ?? this.enableAlwaysOnDisplay,
      enableAnimations: enableAnimations ?? this.enableAnimations,
      style: style ?? this.style,
      animationIntensity: animationIntensity ?? this.animationIntensity,
      customAccentColor: customAccentColor ?? this.customAccentColor,
    );
  }
}

enum NotificationStyle {
  enhanced,
  compact,
  minimal,
  visualizer,
}

/// Provider for notification controller settings
final notificationControllerSettingsProvider = 
    StateNotifierProvider<NotificationControllerSettingsNotifier, NotificationControllerSettings>(
  (ref) => NotificationControllerSettingsNotifier(),
);

class NotificationControllerSettingsNotifier extends StateNotifier<NotificationControllerSettings> {
  NotificationControllerSettingsNotifier() : super(const NotificationControllerSettings());

  void toggleEnhancedController() {
    state = state.copyWith(useEnhancedController: !state.useEnhancedController);
  }

  void toggleBeatResponse() {
    state = state.copyWith(enableBeatResponse: !state.enableBeatResponse);
  }

  void toggleAlwaysOnDisplay() {
    state = state.copyWith(enableAlwaysOnDisplay: !state.enableAlwaysOnDisplay);
  }

  void toggleAnimations() {
    state = state.copyWith(enableAnimations: !state.enableAnimations);
  }

  void setStyle(NotificationStyle style) {
    state = state.copyWith(style: style);
  }

  void setAnimationIntensity(double intensity) {
    state = state.copyWith(animationIntensity: intensity.clamp(0.0, 1.0));
  }

  void setCustomAccentColor(Color? color) {
    state = state.copyWith(customAccentColor: color);
  }
}

/// Provider for beat intensity (used by notification controller)
final beatIntensityProvider = StateProvider<double>((ref) => 0.0);

/// Provider to track always-on display status
final alwaysOnDisplayStatusProvider = StateProvider<bool>((ref) => false);