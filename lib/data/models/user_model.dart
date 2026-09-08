import 'package:cloud_firestore/cloud_firestore.dart';

/// Full user profile model stored per-user in Firestore.
/// Document path: users/{uid}  AND  live_users/{uid}
class UserModel {
  /// Firebase Anonymous Auth UID — the canonical identity key.
  final String uid;

  /// Physical device fingerprint (not the Firebase UID).
  final String deviceId;

  /// Display name chosen by the user during onboarding.
  final String displayName;

  /// Per-user secret passcode for their own dynamic configuration.
  final String userPasscode;

  /// List of room IDs this user has active chat pairs in.
  final List<String> chatPairs;

  /// Online / offline status string.
  final String status;

  /// Whether this user has been granted admin privileges.
  /// Set manually in Firestore: users/{uid} → isAdmin: true
  /// Never written by the app — only by you directly in Firebase Console.
  final bool isAdmin;

  /// Timestamp of last recorded activity.
  final DateTime? lastActive;

  /// Timestamp of last time user was seen online before going offline.
  final DateTime? lastSeen;

  /// FCM push notification token for this device.
  final String? fcmToken;

  /// ID of the chat room the user is currently viewing.
  final String? currentRoomId;

  /// Timestamp when this profile was first created.
  final DateTime? createdAt;

  /// App version string at time of registration.
  final String? appVersion;

  /// Platform string: 'android' | 'ios'
  final String? platform;

  UserModel({
    required this.uid,
    required this.deviceId,
    required this.displayName,
    this.userPasscode = '',
    this.chatPairs = const [],
    this.status = 'online',
    this.isAdmin = false,
    this.lastActive,
    this.lastSeen,
    this.fcmToken,
    this.currentRoomId,
    this.createdAt,
    this.appVersion,
    this.platform,
  });

  /// Full profile map written on first registration.
  /// isAdmin is written as false on first registration so the field EXISTS
  /// in Firestore (making it visible and toggleable in Firebase Console).
  /// It is NEVER set to true by the app — only you can do that manually.
  Map<String, dynamic> toRegistrationMap() => {
        'uid': uid,
        'deviceId': deviceId,
        'name': displayName,
        'displayName': displayName,
        'username': displayName,
        'userName': displayName,
        'userPasscode': userPasscode,
        'chatPairs': chatPairs,
        'status': status,
        // Written as false so the field is visible in Firebase Console.
        // Set to true manually via Console to grant admin access.
        'isAdmin': false,
        'lastActive': FieldValue.serverTimestamp(),
        'lastSeen': lastSeen != null ? Timestamp.fromDate(lastSeen!) : null,
        'fcmToken': fcmToken,
        'currentRoomId': currentRoomId,
        'createdAt': FieldValue.serverTimestamp(),
        'appVersion': appVersion ?? '',
        'platform': platform ?? '',
      };

  /// Presence-only update map.
  Map<String, dynamic> toPresenceMap(bool isOnline) => {
        'uid': uid,
        'status': isOnline ? 'online' : 'offline',
        'lastActive': FieldValue.serverTimestamp(),
        if (!isOnline) 'lastSeen': FieldValue.serverTimestamp(),
        'currentRoomId': isOnline ? currentRoomId : null,
      };

  /// Lightweight map written to live_users — presence + identity only.
  Map<String, dynamic> toLiveUserMap() => {
        'uid': uid,
        'deviceId': deviceId,
        'name': displayName,
        'displayName': displayName,
        'username': displayName,
        'userName': displayName,
        'status': status,
        'lastActive': FieldValue.serverTimestamp(),
        'fcmToken': fcmToken,
        'currentRoomId': currentRoomId,
      };

  factory UserModel.fromFirestore(Map<String, dynamic> data) => UserModel(
        uid: data['uid']?.toString() ?? '',
        deviceId: data['deviceId']?.toString() ?? '',
        displayName: data['displayName']?.toString() ??
            data['name']?.toString() ??
            data['username']?.toString() ??
            data['userName']?.toString() ??
            'Unknown User',
        userPasscode: data['userPasscode']?.toString() ?? '',
        chatPairs: List<String>.from(data['chatPairs'] ?? []),
        status: data['status']?.toString() ?? 'offline',
        isAdmin: data['isAdmin'] == true,
        lastActive: (data['lastActive'] as Timestamp?)?.toDate(),
        lastSeen: (data['lastSeen'] as Timestamp?)?.toDate(),
        fcmToken: data['fcmToken']?.toString(),
        currentRoomId: data['currentRoomId']?.toString(),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
        appVersion: data['appVersion']?.toString(),
        platform: data['platform']?.toString(),
      );

  UserModel copyWith({
    String? displayName,
    String? userPasscode,
    List<String>? chatPairs,
    String? status,
    bool? isAdmin,
    DateTime? lastActive,
    DateTime? lastSeen,
    String? fcmToken,
    String? currentRoomId,
    String? appVersion,
  }) =>
      UserModel(
        uid: uid,
        deviceId: deviceId,
        displayName: displayName ?? this.displayName,
        userPasscode: userPasscode ?? this.userPasscode,
        chatPairs: chatPairs ?? this.chatPairs,
        status: status ?? this.status,
        isAdmin: isAdmin ?? this.isAdmin,
        lastActive: lastActive ?? this.lastActive,
        lastSeen: lastSeen ?? this.lastSeen,
        fcmToken: fcmToken ?? this.fcmToken,
        currentRoomId: currentRoomId ?? this.currentRoomId,
        createdAt: createdAt,
        appVersion: appVersion ?? this.appVersion,
        platform: platform ?? this.platform,
      );
}
