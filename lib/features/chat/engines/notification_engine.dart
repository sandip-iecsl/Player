import 'package:flutter/services.dart';
import '../../../core/events/event_dispatcher.dart';
import '../../../core/events/chat_events.dart';
import '../../../data/services/local_chat_service.dart';
import '../../../core/kernel/i_engine.dart';

class NotificationEngine implements IEngine {
  static final NotificationEngine _instance = NotificationEngine._internal();
  factory NotificationEngine() => _instance;
  NotificationEngine._internal();

  @override
  Future<void> initialize() async {
    // 1. Listen to incoming message creations to trigger sound notifications
    EventDispatcher().on<MessageCreatedEvent>().listen((event) async {
      final myId = await LocalChatService().getDeviceId();
      if (event.message.senderId != myId) {
        SystemSound.play(SystemSoundType.click);
      }
    });

    // 2. Listen to conversation opened event to reset unread badge counts
    EventDispatcher().on<ConversationOpenedEvent>().listen((event) {
      LocalChatService().markRoomAsRead(event.roomId);
    });
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
