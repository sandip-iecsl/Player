import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FcmTokenService {
  static final FcmTokenService _instance = FcmTokenService._internal();
  factory FcmTokenService() => _instance;
  FcmTokenService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> init() async {
    // 1. Request permission for FCM (mainly for iOS or Android 13+) - Silent notifications only
    final settings = await _messaging.requestPermission(
      alert: false,
      badge: false,
      sound: false,
      provisional: false,
    );
    debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

    // Force foreground presentation to be completely silent (no alert, badge, or sound)
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    // 2. Get and save the initial token
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      debugPrint('[FCM] Error getting initial token: $e');
    }

    // 3. Listen for token refreshes
    _messaging.onTokenRefresh.listen((newToken) {
      _saveTokenToFirestore(newToken);
    });

    // 4. Handle foreground silent messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] Received foreground message: ${message.data}');
    });
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    try {
      await _firestore.collection('live_users').doc(user.uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
      debugPrint('[FCM] Saved token for user ${user.uid}');
    } catch (e) {
      debugPrint('[FCM] Error saving token to Firestore: $e');
    }
  }
}
