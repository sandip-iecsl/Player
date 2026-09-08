import '../../../core/events/event_dispatcher.dart';
import '../../../core/events/admin_events.dart';

class AnalyticsEngine {
  static final AnalyticsEngine _instance = AnalyticsEngine._internal();
  factory AnalyticsEngine() => _instance;
  AnalyticsEngine._internal();

  final Map<String, dynamic> _localStats = {
    'commands_executed': 0,
    'events_dispatched': 0,
  };

  void initialize() {
    // Listen to local events to dynamically update stats
    EventDispatcher().on<SyncCompletedEvent>().listen((event) {
      _localStats['commands_executed'] = (_localStats['commands_executed'] as int) + event.count;
      _dispatchUpdate('sync', {'sync_count': event.count});
    });
  }

  Map<String, dynamic> getLocalStats() => _localStats;

  void trackAction(String action, Map<String, dynamic> data) {
    _localStats['events_dispatched'] = (_localStats['events_dispatched'] as int) + 1;
    _dispatchUpdate(action, data);
  }

  void _dispatchUpdate(String category, Map<String, dynamic> data) {
    EventDispatcher().publish(AnalyticsUpdatedEvent(
      eventId: 'analytics_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      category: category,
      data: data,
    ));
  }
}
