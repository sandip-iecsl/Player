abstract class AppEvent {
  final String eventId;
  final DateTime timestamp;

  AppEvent({
    required this.eventId,
    required this.timestamp,
  });
}
