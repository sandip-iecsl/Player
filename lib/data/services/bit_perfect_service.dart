import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';

/// Audio Hardware & Stream Specifications
class AudioHardwareSpecs {
  final int sampleRateHz;
  final int bitDepth;
  final bool isBitPerfectActive;
  final bool isSupported;
  final bool isAndroid14OrHigher;
  final String activeDevice;
  final bool isUsbDac;
  final String codec;
  final String bitrate;

  const AudioHardwareSpecs({
    this.sampleRateHz = 0,
    this.bitDepth = 0,
    this.isBitPerfectActive = false,
    this.isSupported = false,
    this.isAndroid14OrHigher = false,
    this.activeDevice = 'Internal DAC / High-Res Speaker',
    this.isUsbDac = false,
    this.codec = 'AAC / M4A',
    this.bitrate = '320 kbps',
  });

  /// Formatted Sample Rate display (e.g. "44.1 kHz", "48.0 kHz", "96.0 kHz", "192.0 kHz", "2.8 MHz")
  String get sampleRateDisplay {
    if (sampleRateHz <= 0) return 'Unknown';
    if (sampleRateHz >= 1000000) {
      final mhz = (sampleRateHz / 1000000.0).toStringAsFixed(1);
      return '$mhz MHz DSD';
    }
    final khz = (sampleRateHz / 1000.0).toStringAsFixed(1);
    return '$khz kHz';
  }

  /// Formatted Audiophile specs (e.g. "48.0 kHz / 24-bit")
  String get qualityBadgeText => bitDepth > 0
      ? '$sampleRateDisplay / $bitDepth-bit'
      : '$sampleRateDisplay / source depth unknown';

  AudioHardwareSpecs copyWith({
    int? sampleRateHz,
    int? bitDepth,
    bool? isBitPerfectActive,
    bool? isSupported,
    bool? isAndroid14OrHigher,
    String? activeDevice,
    bool? isUsbDac,
    String? codec,
    String? bitrate,
  }) {
    return AudioHardwareSpecs(
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      bitDepth: bitDepth ?? this.bitDepth,
      isBitPerfectActive: isBitPerfectActive ?? this.isBitPerfectActive,
      isSupported: isSupported ?? this.isSupported,
      isAndroid14OrHigher: isAndroid14OrHigher ?? this.isAndroid14OrHigher,
      activeDevice: activeDevice ?? this.activeDevice,
      isUsbDac: isUsbDac ?? this.isUsbDac,
      codec: codec ?? this.codec,
      bitrate: bitrate ?? this.bitrate,
    );
  }
}

/// Bit-Perfect Audiophile Service
/// Interfaces with Android 14+ (API 34) `AudioManager.setPreferredMixerAttributes`
/// with `AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT` to bypass Android OS
/// software resampling, volume scaling, and DSP filters for external DACs & Hi-Fi outputs.
class BitPerfectService {
  static const MethodChannel _channel = MethodChannel('aura_player/bit_perfect');
  static final BitPerfectService _instance = BitPerfectService._internal();
  factory BitPerfectService() => _instance;

  final _specsController = StreamController<AudioHardwareSpecs>.broadcast();
  Stream<AudioHardwareSpecs> get specsStream => _specsController.stream;

  AudioHardwareSpecs _currentSpecs = const AudioHardwareSpecs();
  AudioHardwareSpecs get currentSpecs => _currentSpecs;

  BitPerfectService._internal() {
    _init();
  }

  void _init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAudioDeviceChanged') {
        final device = call.arguments['activeDevice']?.toString() ?? 'Default Audio Output';
        final isUsb = call.arguments['isUsbDac'] as bool? ?? false;
        _updateSpecs(_currentSpecs.copyWith(
          activeDevice: device,
          isUsbDac: isUsb,
        ));
      }
    });
    checkSupport();
  }

  Future<void> checkSupport() async {
    try {
      final res = await _channel.invokeMethod<Map>('isBitPerfectSupported');
      if (res != null) {
        final isSupported = res['isSupported'] as bool? ?? false;
        final isAndroid14 = res['isAndroid14OrHigher'] as bool? ?? false;
        final device = res['activeDevice']?.toString() ?? 'Default Audio Output';
        final isUsb = res['isUsbDac'] as bool? ?? false;
        final isActive = res['isBitPerfectActive'] as bool? ?? false;

        _updateSpecs(_currentSpecs.copyWith(
          isSupported: isSupported,
          isAndroid14OrHigher: isAndroid14,
          activeDevice: device,
          isUsbDac: isUsb,
          isBitPerfectActive: isActive,
        ));
      }
    } catch (_) {}
  }

  /// Configures Bit-Perfect mode for the currently active track
  Future<bool> configureForSong(Song? song, {bool userExplicitEnable = true}) async {
    if (song == null) return false;

    final inferredSampleRate = _inferSampleRate(song);
    final inferredBitDepth = _inferBitDepth(song);
    final inferredCodec = _inferCodec(song);
    final inferredBitrate = song.bitrate ?? '320 kbps';

    try {
      if (userExplicitEnable) {
        final res = await _channel.invokeMethod<Map>('enableBitPerfect', {
          'sampleRate': inferredSampleRate,
          'bitDepth': inferredBitDepth,
        });

        final success = res?['success'] as bool? ?? false;
        final device = res?['activeDevice']?.toString() ?? _currentSpecs.activeDevice;

        _updateSpecs(_currentSpecs.copyWith(
          sampleRateHz: inferredSampleRate,
          bitDepth: inferredBitDepth,
          codec: inferredCodec,
          bitrate: inferredBitrate,
          isBitPerfectActive: success,
          activeDevice: device,
        ));
        return success;
      } else {
        await disableBitPerfect();
        _updateSpecs(_currentSpecs.copyWith(
          sampleRateHz: inferredSampleRate,
          bitDepth: inferredBitDepth,
          codec: inferredCodec,
          bitrate: inferredBitrate,
          isBitPerfectActive: false,
        ));
        return false;
      }
    } catch (e) {
      debugPrint('[BitPerfectService] ⚠️ Configure error: $e');
      _updateSpecs(_currentSpecs.copyWith(
        sampleRateHz: inferredSampleRate,
        bitDepth: inferredBitDepth,
        codec: inferredCodec,
        bitrate: inferredBitrate,
      ));
      return false;
    }
  }

  Future<void> disableBitPerfect() async {
    try {
      await _channel.invokeMethod('disableBitPerfect');
      _updateSpecs(_currentSpecs.copyWith(isBitPerfectActive: false));
    } catch (_) {}
  }

  void _updateSpecs(AudioHardwareSpecs specs) {
    _currentSpecs = specs;
    _specsController.add(specs);
  }

  int _inferSampleRate(Song song) {
    final title = song.title.toLowerCase();
    final fmt = song.formatId?.toLowerCase() ?? '';

    // Hi-Res Studio Master detection (96kHz / 192kHz)
    if (title.contains('96khz') || title.contains('24bit') || title.contains('hi-res') || fmt == 'flac_96') {
      return 96000;
    }
    if (title.contains('192khz') || title.contains('master') || fmt == 'flac_192') {
      return 192000;
    }
    // YouTube audio streams (native Opus / AAC) are encoded at 48.0 kHz
    if (song.isYoutubeImport || song.id.startsWith('yt_') || song.youtubeUrl != null || fmt == '251' || fmt == '140') {
      return 48000;
    }
    // High-Fidelity JioSaavn CD-Quality is 44.1 kHz (or 48.0 kHz on 320k AAC)
    if (song.bitrate != null && song.bitrate!.contains('320')) {
      return 48000;
    }
    return 44100;
  }

  int _inferBitDepth(Song song) {
    final title = song.title.toLowerCase();
    if (title.contains('24bit') || title.contains('hi-res') || title.contains('flac')) {
      return 24;
    }
    if (title.contains('32bit') || title.contains('dsd')) {
      return 32;
    }
    // Lossy AAC/Opus streams do not carry a meaningful source bit depth.
    // Do not present a guessed PCM depth as if it were source fidelity.
    return 0;
  }

  String _inferCodec(Song song) {
    if (song.formatId != null && song.formatId!.isNotEmpty) {
      if (song.formatId == '251' || song.formatId == 'opus') return 'Opus / 48 kHz';
      if (song.formatId == '140' || song.formatId == 'm4a') return 'AAC-LC / M4A';
      if (song.formatId == 'flac') return 'FLAC / Hi-Res';
    }
    if (song.isYoutubeImport || song.id.startsWith('yt_')) return 'M4A / 48 kHz';
    return 'AAC 320 kbps';
  }
}

// ─── Riverpod Providers ───────────────────────────────────────────────────────

final bitPerfectServiceProvider = Provider<BitPerfectService>((ref) {
  return BitPerfectService();
});

final audioSpecsProvider = StreamProvider<AudioHardwareSpecs>((ref) {
  final service = ref.watch(bitPerfectServiceProvider);
  return service.specsStream;
});
