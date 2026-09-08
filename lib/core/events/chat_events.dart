import '../../data/models/chat_message_model.dart';
import 'app_event.dart';

class MessageCreatedEvent extends AppEvent {
  final String roomId;
  final ChatMessageModel message;

  MessageCreatedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.roomId,
    required this.message,
  }) : super(eventId: eventId, timestamp: timestamp);
}

class MessageUpdatedEvent extends AppEvent {
  final String roomId;
  final ChatMessageModel message;

  MessageUpdatedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.roomId,
    required this.message,
  }) : super(eventId: eventId, timestamp: timestamp);
}

class MessageDeletedEvent extends AppEvent {
  final String roomId;
  final String messageId;

  MessageDeletedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.roomId,
    required this.messageId,
  }) : super(eventId: eventId, timestamp: timestamp);
}

class ConversationOpenedEvent extends AppEvent {
  final String roomId;

  ConversationOpenedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.roomId,
  }) : super(eventId: eventId, timestamp: timestamp);
}

class ConversationClosedEvent extends AppEvent {
  final String roomId;

  ConversationClosedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.roomId,
  }) : super(eventId: eventId, timestamp: timestamp);
}

class PresenceChangedEvent extends AppEvent {
  final String userId;
  final String status; // 'online' / 'offline'

  PresenceChangedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.userId,
    required this.status,
  }) : super(eventId: eventId, timestamp: timestamp);
}
