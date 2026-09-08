import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Manages persistent user preferences for download and streaming audio quality
class QualitySettingsService {
  static const String boxName = 'user_settings_box';
  static const String keyDefaultQuality = 'default_download_quality';
  static const String keyStreamingQuality = 'default_streaming_quality';
  static const String keyDataSaverOnCellular = 'data_saver_on_cellular';

  static const String high = 'High'; // 320 kbps
  static const String standard = 'Medium'; // 128 kbps
  static const String dataSaver = 'Data Saver'; // 64 kbps

  static Future<Box> _getBox() async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return await Hive.openBox(boxName);
  }

  /// Gets the user's preferred download quality (defaults to 'High')
  static Future<String> getPreferredDownloadQuality() async {
    try {
      final box = await _getBox();
      return box.get(keyDefaultQuality, defaultValue: high) as String;
    } catch (e) {
      debugPrint('[QualitySettings] Error reading download quality: $e');
      return high;
    }
  }

  /// Sets the user's preferred download quality
  static Future<void> setPreferredDownloadQuality(String quality) async {
    try {
      final box = await _getBox();
      await box.put(keyDefaultQuality, quality);
      debugPrint('[QualitySettings] 💾 Saved preferred download quality: $quality');
    } catch (e) {
      debugPrint('[QualitySettings] Error saving download quality: $e');
    }
  }

  /// Gets whether Data Saver is enabled on cellular mobile connections
  static Future<bool> isDataSaverOnCellularEnabled() async {
    try {
      final box = await _getBox();
      return box.get(keyDataSaverOnCellular, defaultValue: true) as bool;
    } catch (_) {
      return true;
    }
  }

  /// Sets whether Data Saver is enabled on cellular mobile connections
  static Future<void> setDataSaverOnCellular(bool enabled) async {
    try {
      final box = await _getBox();
      await box.put(keyDataSaverOnCellular, enabled);
    } catch (_) {}
  }
}
