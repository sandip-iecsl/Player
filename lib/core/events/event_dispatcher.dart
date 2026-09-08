import 'dart:async';
import 'app_event.dart';

class EventDispatcher {
  static final EventDispatcher _instance = EventDispatcher._internal();
  factory EventDispatcher() => _instance;
  EventDispatcher._internal();

  final _eventController = StreamController<AppEvent>.broadcast();

  /// Publish an event to all subscribers.
  void publish(AppEvent event) {
    _eventController.add(event);
  }

  /// Subscribe to a specific event type.
  Stream<T> on<T extends AppEvent>() {
    if (T == AppEvent) {
      return _eventController.stream.cast<T>();
    }
    return _eventController.stream.where((event) => event is T).cast<T>();
  }

  void dispose() {
    _eventController.close();
  }
}
