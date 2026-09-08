import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/kernel/aura_application.dart';
import '../models/user_model.dart';
import 'presence_service.dart';

/// Single source of truth for all user profile writes.
///
/// Firestore schema written on registration / every launch:
///
/// Default DB ─────────────────────────────────────────────────────────────
///   users/{uid}
///     uid, deviceId, name/displayName/username/userName,
///     userPasscode, chatPairs, status, lastActive, lastSeen,
///     fcmToken, currentRoomId, createdAt, appVersion, platform
///
///   users/{uid}/devices/{deviceId}       ← per-device sub-document
///     deviceId, platform, appVersion, lastSeen, model, osVersion
///
/// Chat DB (databaseId: 'chat') ────────────────────────────────────────────
///   live_users/{uid}
///     uid, deviceId, name/displayName/username/userName,
///     status, lastActive, fcmToken, currentRoomId
///
class UserRegistrationService {
  static final UserRegistrationService _instance =
      UserRegistrationService._internal();
  factory UserRegistrationService() => _instance;
  UserRegistrationService._internal();

  // Default Firestore instance
  final _defaultDb = FirebaseFirestore.instance;

  // Chat Firestore instance (uses default instance as shown in Firebase Console)
  final _chatDb = FirebaseFirestore.instance;

  final _auth = FirebaseAuth.instance;

  static const _prefKeyUserName = 'user_name';
  static const _prefKeyRegistered = 'display_name_registered';
  static const _prefKeyDeviceId = 'cached_device_id';

  // ── Public API ────────────────────────────────────────────────────────────

  /// Called once when the user enters their name for the first time,
  /// and again on every subsequent app launch to refresh presence + profile.
  Future<void> registerOrUpdate(String displayName) async {
    final name = displayName.trim();
    if (name.isEmpty) return;

    try {
      // Ensure Firebase auth is ready
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }

      final uid = AuraApplication().authenticatedUid;
      final deviceId = await _getOrCreateDeviceId();
      final deviceMeta = await _getDeviceMeta();
      final packageInfo = await _getPackageInfo();
      final isFirstTime = !(await _isAlreadyRegistered());

      final user = UserModel(
        uid: uid,
        deviceId: deviceId,
        displayName: name,
        status: 'online',
        platform: Platform.isAndroid ? 'android' : 'ios',
        appVersion: packageInfo,
      );

      // 1. Persist locally first (instant, offline-safe)
      await _persistLocally(name, uid);

      // 2. Write to default Firestore DB — users/{uid}
      await _writeDefaultDb(user, isFirstTime, deviceId, deviceMeta);

      // 3. Write to chat Firestore DB — live_users/{uid}
      await _writeChatDb(user);

      // 4. Start presence heartbeat
      PresenceService().init();

      debugPrint('[UserReg] ✅ Profile registered/updated for $uid as "$name"');
    } catch (e) {
      debugPrint('[UserReg] ❌ Registration error: $e');
      rethrow;
    }
  }

  /// Updates only the user's display name everywhere without a full re-registration.
  Future<void> updateDisplayName(String newName) async {
    final name = newName.trim();
    if (name.isEmpty) return;
    await registerOrUpdate(name);
  }

  /// Adds a new chat pair (roomId) to this user's chatPairs list.
  Future<void> addChatPair(String roomId) async {
    try {
      final uid = AuraApplication().authenticatedUid;
      await _defaultDb.collection('users').doc(uid).update({
        'chatPairs': FieldValue.arrayUnion([roomId]),
      });
      debugPrint('[UserReg] 📎 Chat pair added: $roomId');
    } catch (e) {
      debugPrint('[UserReg] ⚠️ addChatPair failed: $e');
    }
  }

  /// Updates the user's personal passcode (per-user, separate from admin passcode).
  Future<void> updateUserPasscode(String passcode) async {
    try {
      final uid = AuraApplication().authenticatedUid;
      // Write to default DB only — not exposed in live_users (presence db)
      await _defaultDb.collection('users').doc(uid).update({
        'userPasscode': passcode,
      });
      // Cache locally for offline access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_userPasscode', passcode);
      debugPrint('[UserReg] 🔑 User passcode updated.');
    } catch (e) {
      debugPrint('[UserReg] ⚠️ updateUserPasscode failed: $e');
    }
  }

  /// Fetches a user's full profile from the default Firestore DB.
  Future<UserModel?> fetchUser(String uid) async {
    try {
      final doc = await _defaultDb.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return UserModel.fromFirestore(doc.data()!);
      }
    } catch (e) {
      debugPrint('[UserReg] ⚠️ fetchUser failed: $e');
    }
    return null;
  }

  /// Stream of all live users from the chat DB (for chat user discovery).
  Stream<List<UserModel>> streamLiveUsers() {
    return _chatDb.collection('live_users').snapshots().map(
          (snap) => snap.docs
              .map((d) => UserModel.fromFirestore(d.data()))
              .toList(),
        );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _persistLocally(String name, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyUserName, name);
    await prefs.setBool(_prefKeyRegistered, true);

    final box = await Hive.openBox<String>('user_profile_cache');
    await box.put('current_user_name', name);
    await box.put('user_$uid', name);
  }

  Future<void> _writeDefaultDb(
    UserModel user,
    bool isFirstTime,
    String deviceId,
    Map<String, String> deviceMeta,
  ) async {
    final userRef = _defaultDb.collection('users').doc(user.uid);

    if (isFirstTime) {
      // Full document write on first registration
      await userRef.set(user.toRegistrationMap(), SetOptions(merge: true));
    } else {
      // Partial update on subsequent launches — preserve existing data.
      await userRef.set({
        'uid': user.uid,
        'deviceId': deviceId,
        'name': user.displayName,
        'displayName': user.displayName,
        'username': user.displayName,
        'userName': user.displayName,
        'status': 'online',
        'lastActive': FieldValue.serverTimestamp(),
        'platform': user.platform ?? '',
        'appVersion': user.appVersion ?? '',
      }, SetOptions(merge: true));
    }

    // Always write per-device sub-document
    await userRef.collection('devices').doc(deviceId).set({
      'deviceId': deviceId,
      'platform': user.platform ?? '',
      'appVersion': user.appVersion ?? '',
      'lastSeen': FieldValue.serverTimestamp(),
      'model': deviceMeta['model'] ?? '',
      'osVersion': deviceMeta['osVersion'] ?? '',
    }, SetOptions(merge: true));

    // Defensive: ensure an `isAdmin` flag exists on the document so admin UIs
    // can read a consistent role field. Do NOT overwrite if already present.
    // Fetch directly from server to avoid overwriting a server-side true flag with cached null/false data.
    try {
      final snapshot = await userRef.get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      if (data == null || data['isAdmin'] == null) {
        await userRef.set({'isAdmin': false}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _writeChatDb(UserModel user) async {
    await _chatDb.collection('live_users').doc(user.uid).set(
          user.toLiveUserMap(),
          SetOptions(merge: true),
        );
  }

  Future<bool> _isAlreadyRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKeyRegistered) ?? false;
  }

  /// Returns a stable device ID — Firebase UID is used as the canonical device
  /// identity since one anonymous auth session maps to one device installation.
  /// A separate UUID is also cached so it survives auth token refreshes.
  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefKeyDeviceId);
    if (cached != null && cached.isNotEmpty) return cached;

    // Use the Firebase UID as the primary device ID
    final uid = AuraApplication().authenticatedUid;
    await prefs.setString(_prefKeyDeviceId, uid);
    return uid;
  }

  Future<Map<String, String>> _getDeviceMeta() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        return {
          'model': '${android.manufacturer} ${android.model}',
          'osVersion': 'Android ${android.version.release}',
        };
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return {
          'model': ios.model,
          'osVersion': 'iOS ${ios.systemVersion}',
        };
      }
    } catch (_) {}
    return {'model': 'Unknown', 'osVersion': 'Unknown'};
  }

  Future<String> _getPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '';
    }
  }
}
