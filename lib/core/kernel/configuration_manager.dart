import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages runtime configuration values.
/// Passcode getters return null when no value exists — callers must handle
/// null (treat as "not configured") rather than silently falling back to
/// a hardcoded string.
class ConfigurationManager {
  static final ConfigurationManager _instance = ConfigurationManager._internal();
  factory ConfigurationManager() => _instance;
  ConfigurationManager._internal();

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;

    // Always refresh from Firestore server on every boot so every device
    // immediately gets the latest admin-set passcodes — no stale cache.
    debugPrint('[ConfigManager] 🔄 Refreshing config from Firestore server...');
    await _fetchAndCacheFromServer();
  }

  /// Fetches the settings document directly from Firestore server and
  /// overwrites the local SharedPreferences cache.
  Future<void> _fetchAndCacheFromServer() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('map_settings')
          .get(const GetOptions(source: Source.server));

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        // Legacy 'password' key maps to adminPasscode
        final adminPasscode = data['adminPasscode']?.toString() ??
            data['password']?.toString();

        if (adminPasscode != null && adminPasscode.isNotEmpty) {
          await _prefs.setString('cached_adminPasscode', adminPasscode);
        }
        if (data['appLockPasscode'] != null) {
          await _prefs.setString(
              'cached_appLockPasscode', data['appLockPasscode'].toString());
        }
        if (data['secretConsolePasscode'] != null) {
          await _prefs.setString('cached_secretConsolePasscode',
              data['secretConsolePasscode'].toString());
        }
        if (data['chatExpiryHours'] is int) {
          await _prefs.setInt(
              'cached_chatExpiryHours', data['chatExpiryHours'] as int);
        }
        debugPrint('[ConfigManager] ✅ Config refreshed from Firestore.');
      } else {
        debugPrint('[ConfigManager] ⚠️ app_config/map_settings not found.');
      }
    } catch (e) {
      // Network unavailable — keep whatever is already cached locally.
      debugPrint('[ConfigManager] ⚠️ Firestore unreachable ($e) — using cached values.');
    }
  }

  // ── Getters — null means "not set in Firestore yet" ──────────────────────

  /// Returns null when the passcode has never been set in Firestore.
  String? get adminPasscode => _prefs.getString('cached_adminPasscode');

  /// Returns null when the passcode has never been set in Firestore.
  String? get appLockPasscode => _prefs.getString('cached_appLockPasscode');

  /// Returns null when the passcode has never been set in Firestore.
  String? get secretConsolePasscode =>
      _prefs.getString('cached_secretConsolePasscode');

  int get chatExpiryHours => _prefs.getInt('cached_chatExpiryHours') ?? 24;

  // ── Cache writers (used by ConfigurationEngine after a Firestore write) ──

  Future<void> cacheSettings(Map<String, dynamic> settings) async {
    await init();

    final legacyPassword = settings['password']?.toString();
    final adminPasscode =
        settings['adminPasscode']?.toString() ?? legacyPassword;
    final appLockPasscode = settings['appLockPasscode']?.toString();
    final secretConsolePasscode =
        settings['secretConsolePasscode']?.toString();
    final chatExpiryHours = settings['chatExpiryHours'];

    if (adminPasscode != null && adminPasscode.isNotEmpty) {
      await _prefs.setString('cached_adminPasscode', adminPasscode);
    }
    if (appLockPasscode != null && appLockPasscode.isNotEmpty) {
      await _prefs.setString('cached_appLockPasscode', appLockPasscode);
    }
    if (secretConsolePasscode != null && secretConsolePasscode.isNotEmpty) {
      await _prefs.setString(
          'cached_secretConsolePasscode', secretConsolePasscode);
    }
    if (chatExpiryHours is int) {
      await _prefs.setInt('cached_chatExpiryHours', chatExpiryHours);
    }
  }

  Future<void> cachePasscodes({
    required String adminPasscode,
    required String appLockPasscode,
    required String secretConsolePasscode,
    required int chatExpiryHours,
  }) async {
    await cacheSettings({
      'adminPasscode': adminPasscode,
      'appLockPasscode': appLockPasscode,
      'secretConsolePasscode': secretConsolePasscode,
      'chatExpiryHours': chatExpiryHours,
    });
  }
}
