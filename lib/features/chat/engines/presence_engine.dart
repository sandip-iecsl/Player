import '../../../data/services/presence_service.dart';
import '../../../core/events/event_dispatcher.dart';
import '../../../core/events/chat_events.dart';
import '../../../core/kernel/i_engine.dart';

class PresenceEngine implements IEngine {
  static final PresenceEngine _instance = PresenceEngine._internal();
  factory PresenceEngine() => _instance;
  PresenceEngine._internal();

  @override
  Future<void> initialize() async {
    PresenceService().init();

    // Listen to conversation opened/closed events
    EventDispatcher().on<ConversationOpenedEvent>().listen((event) {
      PresenceService().updateActiveRoom(event.roomId);
    });

    EventDispatcher().on<ConversationClosedEvent>().listen((event) {
      PresenceService().updateActiveRoom(null);
    });
  }

  @override
  Future<void> start() async {}

  void updatePresence(bool isOnline) {
    PresenceService().updatePresence(isOnline);
  }

  @override
  Future<void> pause() async {
    updatePresence(false);
  }

  @override
  Future<void> resume() async {
    updatePresence(true);
  }

  @override
  Future<void> stop() async {
    updatePresence(false);
  }

  @override
  Future<void> dispose() async {
    PresenceService().dispose();
  }
}
