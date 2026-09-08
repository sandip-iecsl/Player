import 'app_event.dart';

class SearchRuleCreatedEvent extends AppEvent {
  final String synonymId;
  final String key;
  final String value;

  SearchRuleCreatedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.synonymId,
    required this.key,
    required this.value,
  }) : super(eventId: eventId, timestamp: timestamp);
}

class SearchRuleUpdatedEvent extends AppEvent {
  final String synonymId;
  final String key;
  final String value;

  SearchRuleUpdatedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.synonymId,
    required this.key,
    required this.value,
  }) : super(eventId: eventId, timestamp: timestamp);
}

class SettingsUpdatedEvent extends AppEvent {
  final Map<String, dynamic> settings;

  SettingsUpdatedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.settings,
  }) : super(eventId: eventId, timestamp: timestamp);
}

class UserDeletedEvent extends AppEvent {
  final String userId;

  UserDeletedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.userId,
  }) : super(eventId: eventId, timestamp: timestamp);
}

class SyncCompletedEvent extends AppEvent {
  final int count;

  SyncCompletedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.count,
  }) : super(eventId: eventId, timestamp: timestamp);
}

class QueueFailedEvent extends AppEvent {
  final String error;

  QueueFailedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.error,
  }) : super(eventId: eventId, timestamp: timestamp);
}

class CacheUpdatedEvent extends AppEvent {
  final String cacheKey;

  CacheUpdatedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.cacheKey,
  }) : super(eventId: eventId, timestamp: timestamp);
}

class AnalyticsUpdatedEvent extends AppEvent {
  final String category;
  final Map<String, dynamic> data;

  AnalyticsUpdatedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.category,
    required this.data,
  }) : super(eventId: eventId, timestamp: timestamp);
}
