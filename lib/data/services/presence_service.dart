import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PresenceService with WidgetsBindingObserver {
  static final PresenceService _instance = PresenceService._internal();
  factory PresenceService() => _instance;
  PresenceService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isOnline = false;
  String? _roomId;

  /// Start observing system app lifecycle states.
  void init() {
    WidgetsBinding.instance.addObserver(this);
    // Initial status set
    updatePresence(true);
  }

  /// Sets the currently active Room ID to suppress notifications or update presence detail.
  void updateActiveRoom(String? roomId) {
    _roomId = roomId;
    updatePresence(true);
  }

  /// Sets status to online or offline in Firestore with a redundancy check.
  Future<void> updatePresence(bool isOnline) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    // Safety check: skip redundant writes for both online and offline states
    if (_isOnline == isOnline) return;
    _isOnline = isOnline;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('user_name')?.trim();
      final displayName = savedName != null && savedName.isNotEmpty ? savedName : 'Unknown User';

      await _firestore.collection('live_users').doc(user.uid).set({
        'uid': user.uid,
        'name': displayName,
        'displayName': displayName,
        'username': displayName,
        'status': isOnline ? 'online' : 'offline',
        'lastActive': FieldValue.serverTimestamp(),
        'currentRoomId': isOnline ? _roomId : null,
      }, SetOptions(merge: true));
      debugPrint('[PresenceService] 🟢 Status set to ${isOnline ? "online" : "offline"}');
    } catch (e) {
      debugPrint('[PresenceService] ⚠️ Presence update failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      updatePresence(true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      updatePresence(false);
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    updatePresence(false);
  }
}
