import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../data/models/chat_message_model.dart';
import '../../features/chat/engines/message_engine.dart';
import '../../core/events/event_dispatcher.dart';
import '../../core/events/chat_events.dart';
import '../../core/cache/cache_eviction_engine.dart';

import '../../core/kernel/i_engine.dart';

class ChatRepository implements IEngine {
  static final ChatRepository _instance = ChatRepository._internal();
  factory ChatRepository() => _instance;
  ChatRepository._internal();

  Box<String>? _msgCacheBox;
  final Map<String, List<ChatMessageModel>> _l1MemoryCache = {};

  /// Expose Hive box for direct cache updates (used by stream listeners that
  /// must NOT re-write to Firestore).
  Box<String>? get msgCacheBox => _msgCacheBox;

  /// Directly overwrite the L1 memory cache for a room. Used by stream listeners.
  void updateL1Cache(String roomId, List<ChatMessageModel> messages) {
    _l1MemoryCache[roomId] = messages;
  }


  Future<void> init() async {
    _msgCacheBox = await Hive.openBox<String>('secure_chat_messages');

    // Subscribe to Event Bus to update L1 cache when messages are created/updated
    EventDispatcher().on<MessageCreatedEvent>().listen((event) {
      final list = _l1MemoryCache[event.roomId] ?? [];
      list.insert(0, event.message);
      _l1MemoryCache[event.roomId] = list;
    });

    EventDispatcher().on<MessageUpdatedEvent>().listen((event) {
      final list = _l1MemoryCache[event.roomId] ?? [];
      final idx = list.indexWhere((m) => m.messageId == event.message.messageId);
      if (idx != -1) {
        list[idx] = event.message;
        _l1MemoryCache[event.roomId] = list;
      }
    });

    EventDispatcher().on<MessageDeletedEvent>().listen((event) {
      final list = _l1MemoryCache[event.roomId] ?? [];
      final idx = list.indexWhere((m) => m.messageId == event.messageId);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(
          deletedForEveryone: true,
          text: 'This message was deleted',
        );
        _l1MemoryCache[event.roomId] = list;
      }
    });
  }

  /// Get messages for a roomId utilizing the 3-layer caching pattern (L1 Memory -> L2 Hive -> L3 Firestore)
  Future<List<ChatMessageModel>> getMessages(String roomId, {int limit = 50}) async {
    // Tell CacheEvictionEngine this is the current active chat room (P1 Priority)
    CacheEvictionEngine().setCurrentChat(roomId);

    // 1. Check L1 Memory Cache
    if (_l1MemoryCache.containsKey(roomId)) {
      return _l1MemoryCache[roomId]!.where((msg) => !msg.isArchived).toList();
    }

    // 2. Check L2 Hive Cache
    final List<ChatMessageModel> cached = [];
    if (_msgCacheBox != null) {
      final keys = _msgCacheBox!.keys.where((k) => k.toString().startsWith('${roomId}_'));
      for (final key in keys) {
        final dataStr = _msgCacheBox!.get(key);
        if (dataStr != null) {
          try {
            final json = jsonDecode(dataStr);
            final msg = ChatMessageModel.fromJson(json, json['messageId'] ?? '');
            if (!msg.isArchived) {
              cached.add(msg);
            }
          } catch (_) {}
        }
      }
    }

    if (cached.isNotEmpty) {
      cached.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _l1MemoryCache[roomId] = cached.take(limit).toList();
      return _l1MemoryCache[roomId]!;
    }

    // 3. Fetch from L3 Firestore
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('direct_chats')
          .doc(roomId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get(const GetOptions(source: Source.serverAndCache));

      final messages = snapshot.docs
          .map((doc) => ChatMessageModel.fromJson(doc.data(), doc.id))
          .where((msg) => !msg.isArchived)
          .toList();

      // Update L2 Hive
      if (_msgCacheBox != null) {
        for (final msg in messages) {
          await _msgCacheBox!.put('${roomId}_${msg.messageId}', jsonEncode(msg.toJson()));
        }
      }

      // Update L1 Memory
      _l1MemoryCache[roomId] = messages;
      return messages;
    } catch (e) {
      print('[ChatRepo] Error fetching from cloud: $e');
      return [];
    }
  }

  /// Writes a message to Hive L2 cache, updates L1 memory cache, and
  /// directly syncs to Firestore chat DB. Does NOT re-create the message —
  /// the provided [message] is used as-is (preserving senderId, messageId, etc.).
  Future<void> sendMessage(String roomId, ChatMessageModel message, {String? recipientUid}) async {
    final cacheKey = '${roomId}_${message.messageId}';

    // 1. Update L2 Hive cache
    if (_msgCacheBox != null) {
      await _msgCacheBox!.put(cacheKey, jsonEncode(message.toJson()));
    }

    // 2. Update L1 memory cache (prepend so newest is first)
    final list = List<ChatMessageModel>.from(_l1MemoryCache[roomId] ?? []);
    final existingIdx = list.indexWhere((m) => m.messageId == message.messageId);
    if (existingIdx == -1) {
      list.insert(0, message);
    } else {
      list[existingIdx] = message;
    }
    _l1MemoryCache[roomId] = list;

    // 3. Sync to Firestore chat DB directly
    try {
      final chatDb = FirebaseFirestore.instance;
      await chatDb
          .collection('direct_chats')
          .doc(roomId)
          .collection('messages')
          .doc(message.messageId)
          .set(message.toFirestore(), SetOptions(merge: true));

      final roomParts = roomId.split('_');
      final users = recipientUid != null
          ? [message.senderId, recipientUid]
          : (roomParts.length == 2 ? roomParts : [message.senderId]);

      final String? targetRecipientId = recipientUid ??
          (roomParts.length == 2
              ? roomParts.firstWhere((id) => id != message.senderId, orElse: () => '')
              : null);

      final Map<String, dynamic> roomUpdate = {
        'users': users,
        'lastMessage': message.text,
        'lastSenderId': message.senderId,
        'lastTimestamp': FieldValue.serverTimestamp(),
      };

      if (targetRecipientId != null && targetRecipientId.isNotEmpty) {
        roomUpdate['unreadCounts.$targetRecipientId'] = FieldValue.increment(1);
      }

      await chatDb.collection('direct_chats').doc(roomId).set(roomUpdate, SetOptions(merge: true));
    } catch (e) {
      print('[ChatRepo] Firestore write error: $e');
    }
  }

  /// Star/Unstar a message locally (Hive + L1) and sync to Firestore.
  Future<void> toggleStarMessage(String roomId, ChatMessageModel message) async {
    final updated = message.copyWith(isStarred: !message.isStarred);
    final cacheKey = '${roomId}_${message.messageId}';
    if (_msgCacheBox != null) {
      await _msgCacheBox!.put(cacheKey, jsonEncode(updated.toJson()));
    }
    // Update L1
    final list = List<ChatMessageModel>.from(_l1MemoryCache[roomId] ?? []);
    final idx = list.indexWhere((m) => m.messageId == message.messageId);
    if (idx != -1) list[idx] = updated;
    _l1MemoryCache[roomId] = list;

    try {
      await FirebaseFirestore.instance
          .collection('direct_chats').doc(roomId)
          .collection('messages').doc(message.messageId)
          .update({'isStarred': updated.isStarred});
    } catch (e) { print('[ChatRepo] toggleStar error: $e'); }
  }

  /// Soft deletes a message for everyone (Hive + L1 + Firestore).
  Future<void> deleteForEveryone(String roomId, ChatMessageModel message) async {
    final updated = message.copyWith(
      deletedForEveryone: true,
      text: 'This message was deleted',
    );
    final cacheKey = '${roomId}_${message.messageId}';
    if (_msgCacheBox != null) {
      await _msgCacheBox!.put(cacheKey, jsonEncode(updated.toJson()));
    }
    // Update L1
    final list = List<ChatMessageModel>.from(_l1MemoryCache[roomId] ?? []);
    final idx = list.indexWhere((m) => m.messageId == message.messageId);
    if (idx != -1) list[idx] = updated;
    _l1MemoryCache[roomId] = list;

    try {
      await FirebaseFirestore.instance
          .collection('direct_chats').doc(roomId)
          .collection('messages').doc(message.messageId)
          .update({'deletedForEveryone': true, 'text': 'This message was deleted'});
    } catch (e) { print('[ChatRepo] deleteForEveryone error: $e'); }
  }

  @override
  Future<void> initialize() async {
    await init();
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
