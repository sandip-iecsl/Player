import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum VisualizerStyle {
  // ── Bars ─────────────────────────────────────────────────────────────
  enhancedBars,        // rounded bottom bars, beat-driven height
  enhancedGlowingBars, // mirrored neon glow bars
  // ── Waves ────────────────────────────────────────────────────────────
  liquidWave,          // dual mirrored liquid fill wave
  oscilloscopeWave,    // oscilloscope line that snaps hard to beats
  // ── Rings / Radial ───────────────────────────────────────────────────
  neonRings,           // segmented rotating neon rings
  radialBeat,          // radial rays + circle, beat-driven length
  beatPulseWave,       // expanding shockwave rings + bars
  tunnelRings,         // zoom-in tunnel ovals
  // ── Unique ───────────────────────────────────────────────────────────
  fireWave,            // fire-gradient bottom bars with flicker
  morphBlob,           // organic blob that deforms with beats
  auroraCurtain,       // vertical aurora light curtains, beat-rippled
  plasmaOrb,           // glowing plasma ball with electric arcs
  beatRipple,          // water-ripple rings from center on every beat
  // ── New Effects ──────────────────────────────────────────────────────
  kaleidoscope,        // symmetric mirrored mandala-like patterns
  spectrumBurst,       // particles bursting outward on strong beats
  waveStack,           // stacked layered waveforms moving with beat
  mandalaPattern,      // intricate geometric circles rotating
  equalizerBands,      // frequency-separated colored bands
  beatPulse,           // heart-beat pulsing center with expanding rings
}

class VisualizerSettings {
  final Color barColor;
  final double barWidth;
  final bool autoColor;
  final VisualizerStyle style;
  final bool beatSyncFlash;

  VisualizerSettings({
    this.barColor = const Color(0xFF1DB954),
    this.barWidth = 5.0,
    this.autoColor = true,
    this.style = VisualizerStyle.enhancedBars,
    this.beatSyncFlash = false,
  });

  VisualizerSettings copyWith({
    Color? barColor,
    double? barWidth,
    bool? autoColor,
    VisualizerStyle? style,
    bool? beatSyncFlash,
  }) {
    return VisualizerSettings(
      barColor: barColor ?? this.barColor,
      barWidth: barWidth ?? this.barWidth,
      autoColor: autoColor ?? this.autoColor,
      style: style ?? this.style,
      beatSyncFlash: beatSyncFlash ?? this.beatSyncFlash,
    );
  }
}

final visualizerSettingsProvider =
    StateNotifierProvider<VisualizerSettingsNotifier, VisualizerSettings>(
        (ref) => VisualizerSettingsNotifier());

class VisualizerSettingsNotifier extends StateNotifier<VisualizerSettings> {
  VisualizerSettingsNotifier() : super(VisualizerSettings());

  void setBarColor(Color color) =>
      state = state.copyWith(barColor: color, autoColor: false);
  void setBarWidth(double width) => state = state.copyWith(barWidth: width);
  void toggleAutoColor() =>
      state = state.copyWith(autoColor: !state.autoColor);
  void toggleBeatSync() =>
      state = state.copyWith(beatSyncFlash: !state.beatSyncFlash);
  void setStyle(VisualizerStyle style) =>
      state = state.copyWith(style: style);
}
