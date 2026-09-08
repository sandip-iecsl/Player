import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../data/services/local_chat_service.dart';
import '../../../core/commands/chat_commands.dart';
import '../../../core/sync/adaptive_sync_engine.dart';
import '../../../core/events/event_dispatcher.dart';
import '../../../core/events/chat_events.dart';

class ConversationEngine {
  static final ConversationEngine _instance = ConversationEngine._internal();
  factory ConversationEngine() => _instance;
  ConversationEngine._internal();


  /// Streams active conversations.
  Stream<List<Map<String, dynamic>>> watchConversations() {
    return LocalChatService().getChatConversations();
  }

  /// Create a new chat room document using the Command Queue.
  Future<String> createRoom(String recipientUid, String chatCode) async {
    final myDeviceId = await LocalChatService().getDeviceId();
    final roomId = await LocalChatService().getRoomId(recipientUid);
    final commandId = 'room_${DateTime.now().millisecondsSinceEpoch}_$roomId';

    final roomData = {
      'users': [myDeviceId, recipientUid],
      'lastMessage': 'Waiting for receiver to join...',
      'lastSenderId': myDeviceId,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'chatCode': chatCode,
      'chatCodeStatus': 'pending',
      'chatCodeCreator': myDeviceId,
      'unreadCounts': {
        myDeviceId: 0,
        recipientUid: 0,
      },
    };

    final command = CreateConversationCommand(
      commandId: commandId,
      timestamp: DateTime.now(),
      payload: {
        'roomId': roomId,
        'roomData': roomData,
      },
    );

    await AdaptiveSyncEngine().enqueue(command);
    await AdaptiveSyncEngine().forceSync();
    return roomId;
  }

  /// Mark chat room status as verified.
  Future<void> verifyRoom(String roomId) async {
    final commandId = 'verify_${DateTime.now().millisecondsSinceEpoch}_$roomId';

    final command = CreateConversationCommand(
      commandId: commandId,
      timestamp: DateTime.now(),
      payload: {
        'roomId': roomId,
        'roomData': {
          'chatCodeStatus': 'verified',
          'lastMessage': 'Connected! Say hello 👋',
          'lastTimestamp': FieldValue.serverTimestamp(),
        },
      },
    );

    await AdaptiveSyncEngine().enqueue(command);
    await AdaptiveSyncEngine().forceSync();

    EventDispatcher().publish(ConversationOpenedEvent(
      eventId: commandId,
      timestamp: DateTime.now(),
      roomId: roomId,
    ));
  }
}
