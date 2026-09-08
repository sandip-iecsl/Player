import 'dart:async';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../core/commands/chat_commands.dart';
import '../../../core/sync/adaptive_sync_engine.dart';
import '../../../core/events/event_dispatcher.dart';
import '../../../core/events/chat_events.dart';
import '../../../data/services/local_chat_service.dart';

class MessageEngine {
  static final MessageEngine _instance = MessageEngine._internal();
  factory MessageEngine() => _instance;
  MessageEngine._internal();

  Box<String> get _msgCacheBox => Hive.box<String>('secure_chat_messages');

  /// Send message locally and dispatch sync command.
  Future<void> sendMessage(String roomId, String text, {String? mediaUrl, String? mediaType}) async {
    final senderId = await LocalChatService().getDeviceId();
    const senderName = 'Me'; // Resolved in UI context

    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
    final message = ChatMessageModel(
      messageId: messageId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      timestamp: DateTime.now(),
      mediaUrl: mediaUrl,
      mediaType: mediaType,
    );

    final cacheKey = '${roomId}_$messageId';

    // 1. Update Hive L2 Cache
    await _msgCacheBox.put(cacheKey, jsonEncode(message.toJson()));

    // 2. Dispatch sync command
    final commandId = 'send_$messageId';
    final command = CreateMessageCommand(
      commandId: commandId,
      timestamp: DateTime.now(),
      payload: {
        'roomId': roomId,
        'messageId': messageId,
        'messageData': message.toJson(),
      },
    );

    await AdaptiveSyncEngine().enqueue(command);

    // 3. Publish local event
    EventDispatcher().publish(MessageCreatedEvent(
      eventId: commandId,
      timestamp: DateTime.now(),
      roomId: roomId,
      message: message,
    ));
  }

  /// Star/unstar message locally and sync.
  Future<void> toggleStar(String roomId, ChatMessageModel message) async {
    final updated = message.copyWith(isStarred: !message.isStarred);
    final cacheKey = '${roomId}_${message.messageId}';

    // 1. Save to L2 Hive
    await _msgCacheBox.put(cacheKey, jsonEncode(updated.toJson()));

    // 2. Dispatch sync command
    final commandId = 'star_${message.messageId}';
    final command = UpdateMessageCommand(
      commandId: commandId,
      timestamp: DateTime.now(),
      payload: {
        'roomId': roomId,
        'messageId': message.messageId,
        'updateData': {'isStarred': updated.isStarred},
      },
    );

    await AdaptiveSyncEngine().enqueue(command);

    // 3. Publish event
    EventDispatcher().publish(MessageUpdatedEvent(
      eventId: commandId,
      timestamp: DateTime.now(),
      roomId: roomId,
      message: updated,
    ));
  }

  /// Soft deletes message for everyone.
  Future<void> deleteForEveryone(String roomId, ChatMessageModel message) async {
    final updated = message.copyWith(
      deletedForEveryone: true,
      text: 'This message was deleted',
    );
    final cacheKey = '${roomId}_${message.messageId}';

    // 1. Save to L2 Hive
    await _msgCacheBox.put(cacheKey, jsonEncode(updated.toJson()));

    // 2. Dispatch command
    final commandId = 'delmsg_${message.messageId}';
    final command = DeleteMessageCommand(
      commandId: commandId,
      timestamp: DateTime.now(),
      payload: {
        'roomId': roomId,
        'messageId': message.messageId,
        'updateData': {
          'deletedForEveryone': true,
          'text': 'This message was deleted',
        },
      },
    );

    await AdaptiveSyncEngine().enqueue(command);

    // 3. Publish event
    EventDispatcher().publish(MessageDeletedEvent(
      eventId: commandId,
      timestamp: DateTime.now(),
      roomId: roomId,
      messageId: message.messageId,
    ));
  }

  /// Archive or unarchive message locally.
  Future<void> archiveMessage(String roomId, String messageId, bool archive) async {
    final cacheKey = '${roomId}_$messageId';
    final dataStr = _msgCacheBox.get(cacheKey);

    if (dataStr != null) {
      final json = jsonDecode(dataStr);
      final message = ChatMessageModel.fromJson(json, messageId);
      final updated = message.copyWith(isArchived: archive);

      await _msgCacheBox.put(cacheKey, jsonEncode(updated.toJson()));

      // Dispatch sync command to Firestore
      final commandId = 'archive_${messageId}_$archive';
      final command = UpdateMessageCommand(
        commandId: commandId,
        timestamp: DateTime.now(),
        payload: {
          'roomId': roomId,
          'messageId': messageId,
          'updateData': {'isArchived': archive},
        },
      );

      await AdaptiveSyncEngine().enqueue(command);

      EventDispatcher().publish(MessageUpdatedEvent(
        eventId: commandId,
        timestamp: DateTime.now(),
        roomId: roomId,
        message: updated,
      ));
    }
  }

  /// Prune expired messages: Expire -> Archive Locally -> Hide from UI.
  Future<void> pruneExpiredMessages(String roomId) async {
    try {
      final expiryHours = await LocalChatService.getChatExpiryHours();
      final cutoff = DateTime.now().subtract(Duration(hours: expiryHours));

      // Fetch message list from local Hive to archive them locally
      final keys = _msgCacheBox.keys.where((k) => k.toString().startsWith('${roomId}_'));
      for (final key in keys) {
        final dataStr = _msgCacheBox.get(key);
        if (dataStr != null) {
          final json = jsonDecode(dataStr);
          final timestamp = DateTime.parse(json['timestamp']);
          final isStarred = json['isStarred'] as bool? ?? false;
          final isArchived = json['isArchived'] as bool? ?? false;

          // Starred messages are protected from expiry pruning
          if (isStarred || isArchived) continue;

          if (timestamp.isBefore(cutoff)) {
            final msgId = key.toString().split('_').last;
            // Archive locally
            await archiveMessage(roomId, msgId, true);
          }
        }
      }
    } catch (_) {}
  }

  /// Restores all archived messages in a room.
  Future<void> restoreArchivedMessages(String roomId) async {
    final keys = _msgCacheBox.keys.where((k) => k.toString().startsWith('${roomId}_'));
    for (final key in keys) {
      final dataStr = _msgCacheBox.get(key);
      if (dataStr != null) {
        final json = jsonDecode(dataStr);
        final isArchived = json['isArchived'] as bool? ?? false;

        if (isArchived) {
          final msgId = key.toString().split('_').last;
          await archiveMessage(roomId, msgId, false);
        }
      }
    }
  }
}
