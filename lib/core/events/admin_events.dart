import 'app_event.dart';

class SearchRuleCreatedEvent extends AppEvent {
  final String synonymId;
  final String key;
  final String value;

  SearchRuleCreatedEvent({
    required super.eventId,
    required super.timestamp,
    required this.synonymId,
    required this.key,
    required this.value,
  });
}

class SearchRuleUpdatedEvent extends AppEvent {
  final String synonymId;
  final String key;
  final String value;

  SearchRuleUpdatedEvent({
    required super.eventId,
    required super.timestamp,
    required this.synonymId,
    required this.key,
    required this.value,
  });
}

class SettingsUpdatedEvent extends AppEvent {
  final Map<String, dynamic> settings;

  SettingsUpdatedEvent({
    required super.eventId,
    required super.timestamp,
    required this.settings,
  });
}

class UserDeletedEvent extends AppEvent {
  final String userId;

  UserDeletedEvent({
    required super.eventId,
    required super.timestamp,
    required this.userId,
  });
}

class SyncCompletedEvent extends AppEvent {
  final int count;

  SyncCompletedEvent({
    required super.eventId,
    required super.timestamp,
    required this.count,
  });
}

class QueueFailedEvent extends AppEvent {
  final String error;

  QueueFailedEvent({
    required super.eventId,
    required super.timestamp,
    required this.error,
  });
}

class CacheUpdatedEvent extends AppEvent {
  final String cacheKey;

  CacheUpdatedEvent({
    required super.eventId,
    required super.timestamp,
    required this.cacheKey,
  });
}

class AnalyticsUpdatedEvent extends AppEvent {
  final String category;
  final Map<String, dynamic> data;

  AnalyticsUpdatedEvent({
    required super.eventId,
    required super.timestamp,
    required this.category,
    required this.data,
  });
}
