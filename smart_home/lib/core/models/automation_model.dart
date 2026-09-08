import 'package:cloud_firestore/cloud_firestore.dart';

enum AutomationTrigger { time, sunset, sunrise, vacation, sleep }
enum AutomationRepeat { once, daily, weekdays, weekends, custom }

class AutomationModel {
  final String id;
  final String name;
  final AutomationTrigger trigger;
  final AutomationRepeat repeat;
  final String? time; // HH:mm
  final List<String> deviceIds;
  final bool targetState;
  final bool enabled;
  final List<int> weekdays; // 1=Mon..7=Sun
  final DateTime? createdAt;

  const AutomationModel({
    required this.id,
    required this.name,
    required this.trigger,
    required this.repeat,
    this.time,
    required this.deviceIds,
    required this.targetState,
    required this.enabled,
    required this.weekdays,
    this.createdAt,
  });

  factory AutomationModel.fromFirestore(Map<String, dynamic> data, String id) => AutomationModel(
    id: id,
    name: data['name'] ?? '',
    trigger: AutomationTrigger.values.firstWhere(
      (t) => t.name == (data['trigger'] ?? 'time'),
      orElse: () => AutomationTrigger.time,
    ),
    repeat: AutomationRepeat.values.firstWhere(
      (r) => r.name == (data['repeat'] ?? 'once'),
      orElse: () => AutomationRepeat.once,
    ),
    time: data['time'],
    deviceIds: List<String>.from(data['deviceIds'] ?? []),
    targetState: data['targetState'] ?? false,
    enabled: data['enabled'] ?? true,
    weekdays: List<int>.from(data['weekdays'] ?? []),
    createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
  );

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'trigger': trigger.name,
    'repeat': repeat.name,
    'time': time,
    'deviceIds': deviceIds,
    'targetState': targetState,
    'enabled': enabled,
    'weekdays': weekdays,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
  };

  AutomationModel copyWith({
    String? name,
    AutomationTrigger? trigger,
    AutomationRepeat? repeat,
    String? time,
    List<String>? deviceIds,
    bool? targetState,
    bool? enabled,
    List<int>? weekdays,
  }) {
    return AutomationModel(
      id: id,
      name: name ?? this.name,
      trigger: trigger ?? this.trigger,
      repeat: repeat ?? this.repeat,
      time: time ?? this.time,
      deviceIds: deviceIds ?? this.deviceIds,
      targetState: targetState ?? this.targetState,
      enabled: enabled ?? this.enabled,
      weekdays: weekdays ?? this.weekdays,
      createdAt: createdAt,
    );
  }
}
