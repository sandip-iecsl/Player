import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/kernel/aura_application.dart';

/// Result returned by [SecurityEngine.validateAdminAccess].
class AdminAccessResult {
  /// Whether access was granted.
  final bool granted;

  /// Human-readable reason for denial (null when granted).
  final String? denyReason;

  const AdminAccessResult.granted()
      : granted = true,
        denyReason = null;

  const AdminAccessResult.denied(String reason)
      : granted = false,
        denyReason = reason;
}

/// Central security validator.
///
/// All checks fetch directly from Firestore server — no local cache,
/// no hardcoded fallbacks. Fail-closed: network error = access denied.
class SecurityEngine {
  static final SecurityEngine _instance = SecurityEngine._internal();
  factory SecurityEngine() => _instance;
  SecurityEngine._internal();

  static const _configCollection = 'app_config';
  static const _configDocument   = 'map_settings';
  static const _usersCollection  = 'users';

  // ── Firestore fetchers ────────────────────────────────────────────────────

  /// Fetches app_config/map_settings from Firestore server.
  Future<Map<String, dynamic>> _fetchLiveSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_configCollection)
          .doc(_configDocument)
          .get(const GetOptions(source: Source.server));
      if (doc.exists && doc.data() != null) {
        return Map<String, dynamic>.from(doc.data()!);
      }
    } catch (e) {
      debugPrint('[SecurityEngine] ⚠️ app_config fetch failed: $e');
    }
    return {};
  }

  /// Fetches the current user's profile document from users/{uid}.
  Future<Map<String, dynamic>> _fetchCurrentUserProfile() async {
    try {
      final uid = AuraApplication().authenticatedUid;
      final doc = await FirebaseFirestore.instance
          .collection(_usersCollection)
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      if (doc.exists && doc.data() != null) {
        return Map<String, dynamic>.from(doc.data()!);
      }
    } catch (e) {
      debugPrint('[SecurityEngine] ⚠️ user profile fetch failed: $e');
    }
    return {};
  }

  // ── Admin access — dual check ─────────────────────────────────────────────

  /// Full admin access gate.
  ///
  /// Both conditions must be true to grant access:
  ///   1. Entered passcode == app_config/map_settings.adminPasscode
  ///   2. users/{uid}.isAdmin == true
  ///
  /// Returns [AdminAccessResult] with a specific deny reason so the UI
  /// can show the right message to the user.
  Future<AdminAccessResult> validateAdminAccess(String enteredPasscode) async {
    if (enteredPasscode.isEmpty) {
      return const AdminAccessResult.denied('Passcode cannot be empty.');
    }

    // Run both Firestore fetches in parallel for speed
    final results = await Future.wait([
      _fetchLiveSettings(),
      _fetchCurrentUserProfile(),
    ]);

    final settings    = results[0];
    final userProfile = results[1];

    // ── Check 1: Password ────────────────────────────────────────────────
    final correctPass = settings['adminPasscode']?.toString() ??
        settings['password']?.toString();

    if (correctPass == null || correctPass.isEmpty) {
      debugPrint('[SecurityEngine] ⚠️ adminPasscode not configured in Firestore.');
      return const AdminAccessResult.denied(
          'Admin passcode is not configured. Contact the app owner.');
    }

    if (enteredPasscode != correctPass) {
      debugPrint('[SecurityEngine] ❌ Admin passcode mismatch.');
      return const AdminAccessResult.denied('Incorrect passcode.');
    }

    // ── Check 2: isAdmin flag on user document ───────────────────────────
    final isAdmin = userProfile['isAdmin'] == true;

    if (!isAdmin) {
      debugPrint('[SecurityEngine] 🚫 User is not an admin.');
      return const AdminAccessResult.denied(
          'Your account does not have admin privileges.');
    }

    debugPrint('[SecurityEngine] ✅ Admin access granted.');
    return const AdminAccessResult.granted();
  }

  // ── Individual passcode validators (used outside admin gate) ─────────────

  /// Validate Admin Passcode only (password check, no isAdmin check).
  /// Use [validateAdminAccess] for full admin gate.
  Future<bool> validateAdminPasscode(String entered) async {
    if (entered.isEmpty) return false;
    final data = await _fetchLiveSettings();
    final correct = data['adminPasscode']?.toString() ??
        data['password']?.toString();
    if (correct == null || correct.isEmpty) return false;
    return entered == correct;
  }

  /// Validate App Lock Passcode directly against Firestore.
  Future<bool> validateAppLockPasscode(String entered) async {
    if (entered.isEmpty) return false;
    final data = await _fetchLiveSettings();
    final correct = data['appLockPasscode']?.toString();
    if (correct == null || correct.isEmpty) return false;
    return entered == correct;
  }

  /// Validate Secret Console Passcode directly against Firestore.
  Future<bool> validateSecretConsolePasscode(String entered) async {
    if (entered.isEmpty) return false;
    final data = await _fetchLiveSettings();
    final correct = data['secretConsolePasscode']?.toString();
    if (correct == null || correct.isEmpty) return false;
    return entered == correct;
  }

  // ── isAdmin helpers ───────────────────────────────────────────────────────

  /// Returns true if the current user has isAdmin == true in Firestore.
  /// Use this to show/hide the Admin Panel tile in the UI.
  Future<bool> isCurrentUserAdmin() async {
    final profile = await _fetchCurrentUserProfile();
    return profile['isAdmin'] == true;
  }
}
