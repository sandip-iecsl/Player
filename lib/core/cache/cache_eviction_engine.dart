import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../commands/app_command_factory.dart';

import '../kernel/i_engine.dart';

class CacheEvictionEngine implements IEngine {
  static final CacheEvictionEngine _instance = CacheEvictionEngine._internal();
  factory CacheEvictionEngine() => _instance;
  CacheEvictionEngine._internal();

  String? _currentChatRoomId;
  Set<String> _pinnedRooms = {};
  Set<String> _archivedRooms = {};

  @override
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _pinnedRooms = prefs.getStringList('pinned_chat_rooms')?.toSet() ?? {};
    _archivedRooms = prefs.getStringList('archived_chat_rooms')?.toSet() ?? {};
    debugPrint('[CacheEvictionEngine] 📦 Loaded ${_pinnedRooms.length} pinned, ${_archivedRooms.length} archived rooms.');
  }

  void setCurrentChat(String? roomId) {
    _currentChatRoomId = roomId;
    debugPrint('[CacheEvictionEngine] 🎯 Current active chat room set to: $roomId');
  }

  Future<void> pinRoom(String roomId, bool pin) async {
    final prefs = await SharedPreferences.getInstance();
    if (pin) {
      _pinnedRooms.add(roomId);
    } else {
      _pinnedRooms.remove(roomId);
    }
    await prefs.setStringList('pinned_chat_rooms', _pinnedRooms.toList());
    debugPrint('[CacheEvictionEngine] 📌 Room $roomId pin status: $pin');
  }

  Future<void> archiveRoom(String roomId, bool archive) async {
    final prefs = await SharedPreferences.getInstance();
    if (archive) {
      _archivedRooms.add(roomId);
    } else {
      _archivedRooms.remove(roomId);
    }
    await prefs.setStringList('archived_chat_rooms', _archivedRooms.toList());
    debugPrint('[CacheEvictionEngine] 🗄️ Room $roomId archive status: $archive');
  }

  bool isPinned(String roomId) => _pinnedRooms.contains(roomId);
  bool isArchived(String roomId) => _archivedRooms.contains(roomId);

  /// Performs cache eviction based on priority categories (P1 to P5).
  /// Safely avoids deleting any unsynced data.
  Future<void> runEviction() async {
    try {
      final msgBox = Hive.box<String>('secure_chat_messages');
      final queueBox = Hive.box<String>('command_sync_queue');

      // 1. Gather all message IDs that are currently unsynced
      final Set<String> unsyncedMessageIds = {};
      for (final key in queueBox.keys) {
        final val = queueBox.get(key);
        if (val != null) {
          try {
            final cmd = AppCommandFactory.fromJson(jsonDecode(val));
            final payloadMsgId = cmd.payload['messageId'];
            if (payloadMsgId != null) {
              unsyncedMessageIds.add(payloadMsgId as String);
            }
          } catch (_) {}
        }
      }

      // 2. Iterate and classify cached messages
      final keys = msgBox.keys.toList();
      final Map<String, List<String>> roomMessageKeys = {};

      for (final key in keys) {
        final parts = key.toString().split('_');
        if (parts.length < 2) continue;
        final roomId = parts[0];
        roomMessageKeys.putIfAbsent(roomId, () => []).add(key.toString());
      }

      final List<String> keysToEvict = [];

      for (final roomId in roomMessageKeys.keys) {
        // P1: Current active chat
        if (roomId == _currentChatRoomId) continue;

        // P2: Pinned chats
        if (_pinnedRooms.contains(roomId)) continue;

        // Determine eviction priority based on room category
        bool isArchived = _archivedRooms.contains(roomId);

        final msgKeys = roomMessageKeys[roomId]!;
        for (final msgKey in msgKeys) {
          final parts = msgKey.split('_');
          final msgId = parts.last;

          // Never evict unsynced data
          if (unsyncedMessageIds.contains(msgId)) continue;

          // Eviction rules
          if (isArchived) {
            // P4: Archived chats (Evicted secondary)
            keysToEvict.add(msgKey);
          } else {
            // P5: Old messages (Evicted primary)
            // Let's check message metadata if parsed
            final dataStr = msgBox.get(msgKey);
            if (dataStr != null) {
              try {
                final data = jsonDecode(dataStr);
                final timestamp = DateTime.parse(data['timestamp']);
                final isStarred = data['isStarred'] as bool? ?? false;

                // Starred messages should not be evicted easily
                if (isStarred) continue;

                // Older than 7 days gets evicted
                if (DateTime.now().difference(timestamp).inDays > 7) {
                  keysToEvict.add(msgKey);
                }
              } catch (_) {
                // If parsing fails, treat as generic old message
                keysToEvict.add(msgKey);
              }
            }
          }
        }
      }

      if (keysToEvict.isNotEmpty) {
        await msgBox.deleteAll(keysToEvict);
        debugPrint('[CacheEvictionEngine] 🧹 Evicted ${keysToEvict.length} messages from Hive cache.');
      }
    } catch (e) {
      debugPrint('[CacheEvictionEngine] ⚠️ Eviction failed: $e');
    }
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
