import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../core/kernel/aura_application.dart';
import '../../features/chat/engines/conversation_engine.dart';
import 'presence_service.dart';
import 'user_registration_service.dart';

class LocalChatService {
  static final LocalChatService _instance = LocalChatService._internal();
  factory LocalChatService() => _instance;
  LocalChatService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription? _pendingQueueSub;

  Future<String> getDeviceId() async {
    return AuraApplication().authenticatedUid;
  }

  String resolveDisplayName(Map<String, dynamic>? data, {String fallback = 'Unknown User'}) {
    final candidates = <String?>[
      data?['displayName']?.toString(),
      data?['name']?.toString(),
      data?['username']?.toString(),
      data?['userName']?.toString(),
    ];

    for (final candidate in candidates) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return fallback;
  }

  Future<void> syncUserProfile(String name) async {
    // Delegate to the canonical UserRegistrationService
    await UserRegistrationService().registerOrUpdate(name);
  }

  /// Register the current user — delegates to UserRegistrationService.
  Future<void> registerUser(String name) async {
    try {
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }
      await UserRegistrationService().registerOrUpdate(name);
      listenToPendingQueue();
    } catch (e) {
      debugPrint('[LocalChat] Registration error: $e');
    }
  }

  /// Stream of all users available for chat
  Stream<List<Map<String, dynamic>>> getChatUsers() {
    print('[LocalChat] Subscribing to live_users stream...');
    return _firestore.collection('live_users').snapshots().map((snapshot) {
      print('[LocalChat] Received stream snapshot with ${snapshot.docs.length} users');
      return snapshot.docs
          .map((doc) {
            final data = Map<String, dynamic>.from(doc.data());
            data['name'] = resolveDisplayName(data, fallback: 'Unknown User');
            return data;
          })
          .toList();
    }).handleError((err) {
      print('[LocalChat] Chat users stream error: $err');
    }).asBroadcastStream();
  }

  /// Fetch all registered users — reads from BOTH databases with server source
  /// to guarantee fresh results even on first launch.
  Future<List<Map<String, dynamic>>> getChatUsersOnce() async {
    final results = <String, Map<String, dynamic>>{}; // keyed by uid for dedup

    // 1. Read live_users from chat DB (has presence/status info)
    try {
      final chatSnap = await _firestore
          .collection('live_users')
          .get(const GetOptions(source: Source.server));
      for (final doc in chatSnap.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['uid'] ??= doc.id;
        data['name'] = resolveDisplayName(data, fallback: 'Unknown User');
        results[doc.id] = data;
      }
    } catch (e) {
      debugPrint('[LocalChat] live_users fetch error: $e');
    }

    // 2. Read users from default DB (has all registered users)
    try {
      final defaultSnap = await FirebaseFirestore.instance
          .collection('users')
          .get(const GetOptions(source: Source.server));
      for (final doc in defaultSnap.docs) {
        if (results.containsKey(doc.id)) continue; // already have fresher data
        final data = Map<String, dynamic>.from(doc.data());
        data['uid'] ??= doc.id;
        data['name'] = resolveDisplayName(data, fallback: 'Unknown User');
        results[doc.id] = data;
      }
    } catch (e) {
      debugPrint('[LocalChat] users fetch error: $e');
    }

    // Sort: online first, then by name
    final list = results.values.toList();
    list.sort((a, b) {
      final aOnline = a['status'] == 'online' ? 0 : 1;
      final bOnline = b['status'] == 'online' ? 0 : 1;
      if (aOnline != bOnline) return aOnline.compareTo(bOnline);
      return (a['name'] as String).compareTo(b['name'] as String);
    });

    return list;
  }

  /// Unique roomId based on alphabetical sorting of UIDs
  Future<String> getRoomId(String recipientUid) async {
    final myDeviceId = await getDeviceId();
    return myDeviceId.compareTo(recipientUid) < 0
        ? '${myDeviceId}_$recipientUid'
        : '${recipientUid}_$myDeviceId';
  }

  /// Stream messages for a specific chat room
  Stream<QuerySnapshot> getMessages(String roomId) {
    return _firestore
        .collection('direct_chats')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
  }

  /// Send a direct message in a specific chat room
  Future<void> sendDirectMessage(
      String recipientUid, String recipientName, String senderName, String text) async {
    try {
      final myDeviceId = await getDeviceId();
      final roomId = await getRoomId(recipientUid);
      final chatRef = _firestore.collection('direct_chats').doc(roomId);

      final messageData = {
        'senderId': myDeviceId,
        'senderName': senderName,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      };

      // Query recipient status in Firestore to check if they are viewing this room
      final recipientDoc = await _firestore.collection('live_users').doc(recipientUid).get();
      bool isRecipientViewing = false;
      
      if (recipientDoc.exists) {
        final recipientData = recipientDoc.data();
        final currentRoomId = recipientData?['currentRoomId'] as String? ?? '';
        final status = recipientData?['status'] as String? ?? 'offline';
        final lastActive = recipientData?['lastActive'] as Timestamp?;
        
        // Receiver is viewing if status is online, viewing our room, and pinged in last 15 seconds
        if (status == 'online' && currentRoomId == roomId && lastActive != null) {
          final diff = DateTime.now().difference(lastActive.toDate()).inSeconds;
          if (diff <= 15) {
            isRecipientViewing = true;
          }
        }
      }

      await _firestore.runTransaction((transaction) async {
        transaction.set(chatRef, {
          'users': [myDeviceId, recipientUid],
          'lastMessage': text,
          'lastSenderId': myDeviceId,
          'lastTimestamp': FieldValue.serverTimestamp(),
          // Incremental Unread badge counter for recipient if they are not active in this room
          if (!isRecipientViewing)
            'unreadCounts.$recipientUid': FieldValue.increment(1),
        }, SetOptions(merge: true));

        transaction.set(chatRef.collection('messages').doc(), messageData);
      });
    } catch (e) {
      print('[LocalChat] Send message error on default db: $e');
    }
  }

  /// Stream of only the active chat rooms on the secondary Firestore instance that the current user is part of
  Stream<List<Map<String, dynamic>>> getChatRooms() {
    return Stream.fromFuture(getDeviceId()).asyncExpand((myDeviceId) {
      return _firestore
          .collection('direct_chats')
          .where('users', arrayContains: myDeviceId)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['roomId'] = doc.id;
          return data;
        }).toList();
      });
    }).asBroadcastStream();
  }

  /// Fetch all active chat rooms once from the secondary Firestore instance (Admin tool only)
  Future<List<Map<String, dynamic>>> getAllChatRoomsOnce() async {
    try {
      final snapshot = await _firestore.collection('direct_chats').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['roomId'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('[LocalChat] Error getting all rooms once: $e');
      return [];
    }
  }

  /// Stream of all conversations combining chat_users and direct_chats.
  /// Re-fetches users from Firestore whenever the room list updates so that
  /// newly verified chat partners appear without requiring a screen unbind/rebind.
  Stream<List<Map<String, dynamic>>> getChatConversations() {
    late StreamController<List<Map<String, dynamic>>> controller;
    StreamSubscription? roomsSub;
    List<Map<String, dynamic>> users = [];
    List<Map<String, dynamic>> rooms = [];
    String? myId;

    void emitCombined() {
      if (controller.isClosed) return;
      if (myId == null) return;

      final conversations = <Map<String, dynamic>>[];
      for (final room in rooms) {
        final roomId = room['roomId'] as String? ?? '';
        final roomUsers = (room['users'] as List?)?.cast<String>() ?? [];

        String otherUid = roomUsers.firstWhere((u) => u != myId, orElse: () => '');
        if (otherUid.isEmpty) {
          final parts = roomId.split('_');
          if (parts.length == 2) {
            otherUid = parts.firstWhere((u) => u != myId, orElse: () => '');
          }
        }
        if (otherUid.isEmpty) continue;

        final userProfile = users.firstWhere(
          (u) => u['uid'] == otherUid,
          orElse: () => {},
        );

        final name = resolveDisplayName(userProfile, fallback: 'Unknown User');
        final lastMessage = room['lastMessage'] as String?;
        final lastTimestamp = room['lastTimestamp'] as Timestamp?;
        final lastSenderId = room['lastSenderId'] as String?;
        final chatCode = room['chatCode'] as String?;
        final chatCodeStatus = room['chatCodeStatus'] as String?;
        final chatCodeCreator = room['chatCodeCreator'] as String?;
        final unreadCount = room['unreadCounts']?[myId] as int? ?? 0;

        conversations.add({
          'uid': otherUid,
          'name': name,
          'lastActive': userProfile['lastActive'] ?? lastTimestamp,
          'status': userProfile['status'] as String? ?? 'offline',
          'lastMessage': lastMessage,
          'lastTimestamp': lastTimestamp,
          'lastSenderId': lastSenderId,
          'roomId': roomId,
          'chatCode': chatCode,
          'chatCodeStatus': chatCodeStatus,
          'chatCodeCreator': chatCodeCreator,
          'unreadCount': unreadCount,
        });
      }

      // Sort: most recent first
      conversations.sort((a, b) {
        final tsA = a['lastTimestamp'] as Timestamp?;
        final tsB = b['lastTimestamp'] as Timestamp?;
        if (tsA != null && tsB != null) {
          return tsB.compareTo(tsA);
        } else if (tsA != null) {
          return -1;
        } else if (tsB != null) {
          return 1;
        } else {
          return 0;
        }
      });

      controller.add(conversations);
    }

    Future<void> refreshUsers() async {
      try {
        users = await getChatUsersOnce();
      } catch (e) {
        debugPrint('[LocalChat] refreshUsers error: $e');
      }
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () async {
        try {
          myId = await getDeviceId();
          await refreshUsers();
          emitCombined();

          // Listen to our chat rooms in real-time
          // Re-fetch users on each room update so newly connected partners appear
          roomsSub = getChatRooms().listen(
            (r) async {
              rooms = r;
              // Refresh user list each time rooms update (handles new connections)
              await refreshUsers();
              emitCombined();
            },
            onError: (err) => print('[LocalChat] Combined stream rooms error: $err'),
          );
        } catch (e) {
          print('[LocalChat] Error starting combined stream: $e');
          if (!controller.isClosed) {
            controller.add([]);
          }
        }
      },
      onCancel: () {
        roomsSub?.cancel();
      },
    );

    return controller.stream;
  }


  /// Create a new chat room with a passcode
  Future<String> createChatRoom(String recipientUid, String chatCode) async {
    try {
      final roomId = await ConversationEngine().createRoom(recipientUid, chatCode);
      // Record this chat pair on both users' profiles
      await UserRegistrationService().addChatPair(roomId);
      return roomId;
    } catch (e) {
      debugPrint('[LocalChat] Create chat room error: $e');
      rethrow;
    }
  }

  /// Mark chat room as verified
  Future<void> verifyChatRoom(String roomId) async {
    try {
      await _firestore.collection('direct_chats').doc(roomId).set({
        'chatCodeStatus': 'verified',
        'lastMessage': 'Connected! Say hello 👋',
        'lastTimestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('[LocalChat] Verify chat room error: $e');
    }
  }

  /// Reset room unread badge counts on entering chat room
  Future<void> markRoomAsRead(String roomId) async {
    try {
      final myDeviceId = await getDeviceId();
      await _firestore.collection('direct_chats').doc(roomId).update({
        'unreadCounts.$myDeviceId': 0,
      });
    } catch (e) {
      print('[LocalChat] Mark room as read error: $e');
    }
  }

  /// Set the current viewed room ID to suppress foreground notifications when viewing the thread
  Future<void> updateCurrentRoom(String? roomId) async {
    try {
      final uid = await getDeviceId();
      await _firestore.collection('live_users').doc(uid).update({
        'currentRoomId': roomId,
      });
    } catch (e) {
      print('[LocalChat] Update current room error: $e');
    }
  }

  /// Real-Time Presence Keep-Alive Heartbeat Timer (Delegated to lifecycle observer)
  void startHeartbeat() {
    PresenceService().updatePresence(true);
  }

  /// Mark user as Offline when app is closed / backgrounded
  void stopHeartbeat() {
    PresenceService().updatePresence(false);
  }

  /// Listen to pending deliveries queue while receiver connects to internet/opens the app
  void listenToPendingQueue() async {
    // Disabled to save Firestore reads/listeners in free tier
    return;
  }

  void stopPendingQueueListener() {
    _pendingQueueSub?.cancel();
  }

  /// Stream of room document metadata
  Stream<DocumentSnapshot> getRoomStream(String roomId) {
    return _firestore.collection('direct_chats').doc(roomId).snapshots();
  }

  /// Read the dynamic chat expiry setting (in hours) from the default Firestore database
  static Future<int> getChatExpiryHours() async {
    return 24; // Default to 24 hours locally — ZERO Firestore reads
  }

  /// Prune expired messages in a room
  Future<void> pruneExpiredMessages(String roomId) async {
    try {
      final expiryHours = await getChatExpiryHours();
      final cutoff = DateTime.now().subtract(Duration(hours: expiryHours));
      final expiredMessages = await _firestore
          .collection('direct_chats')
          .doc(roomId)
          .collection('messages')
          .where('timestamp', isLessThan: Timestamp.fromDate(cutoff))
          .get();

      if (expiredMessages.docs.isNotEmpty) {
        print('[LocalChat] Pruning ${expiredMessages.docs.length} expired messages in room $roomId');
        final batch = _firestore.batch();
        for (var doc in expiredMessages.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      print('[LocalChat] Prune error: $e');
    }
  }

  /// Clear all messages in a specific chat room
  Future<void> clearChat(String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('direct_chats')
          .doc(roomId)
          .collection('messages')
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // Reset lastMessage metadata
      await _firestore.collection('direct_chats').doc(roomId).update({
        'lastMessage': 'Chat cleared',
        'lastTimestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('[LocalChat] Clear chat error: $e');
    }
  }
}
