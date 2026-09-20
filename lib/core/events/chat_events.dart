import '../../data/models/chat_message_model.dart';
import 'app_event.dart';

class MessageCreatedEvent extends AppEvent {
  final String roomId;
  final ChatMessageModel message;

  MessageCreatedEvent({
    required super.eventId,
    required super.timestamp,
    required this.roomId,
    required this.message,
  });
}

class MessageUpdatedEvent extends AppEvent {
  final String roomId;
  final ChatMessageModel message;

  MessageUpdatedEvent({
    required super.eventId,
    required super.timestamp,
    required this.roomId,
    required this.message,
  });
}

class MessageDeletedEvent extends AppEvent {
  final String roomId;
  final String messageId;

  MessageDeletedEvent({
    required super.eventId,
    required super.timestamp,
    required this.roomId,
    required this.messageId,
  });
}

class ConversationOpenedEvent extends AppEvent {
  final String roomId;

  ConversationOpenedEvent({
    required super.eventId,
    required super.timestamp,
    required this.roomId,
  });
}

class ConversationClosedEvent extends AppEvent {
  final String roomId;

  ConversationClosedEvent({
    required super.eventId,
    required super.timestamp,
    required this.roomId,
  });
}

class PresenceChangedEvent extends AppEvent {
  final String userId;
  final String status; // 'online' / 'offline'

  PresenceChangedEvent({
    required super.eventId,
    required super.timestamp,
    required this.userId,
    required this.status,
  });
}
