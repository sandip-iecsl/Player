enum DeviceType {
  bulb,
  fan,
  ac,
  plug,
  switchDevice,
  pump,
  motor,
  tv,
  speaker,
  heater,
  custom,
}

extension DeviceTypeExtension on DeviceType {
  String get label {
    switch (this) {
      case DeviceType.bulb:
        return 'Light Bulb';
      case DeviceType.fan:
        return 'Fan';
      case DeviceType.ac:
        return 'AC';
      case DeviceType.plug:
        return 'Smart Plug';
      case DeviceType.switchDevice:
        return 'Switch';
      case DeviceType.pump:
        return 'Water Pump';
      case DeviceType.motor:
        return 'Motor';
      case DeviceType.tv:
        return 'TV';
      case DeviceType.speaker:
        return 'Speaker';
      case DeviceType.heater:
        return 'Heater';
      case DeviceType.custom:
        return 'Custom';
    }
  }

  String get iconAsset {
    switch (this) {
      case DeviceType.bulb:
        return '💡';
      case DeviceType.fan:
        return '🌀';
      case DeviceType.ac:
        return '❄️';
      case DeviceType.plug:
        return '🔌';
      case DeviceType.switchDevice:
        return '🔘';
      case DeviceType.pump:
        return '💧';
      case DeviceType.motor:
        return '⚙️';
      case DeviceType.tv:
        return '📺';
      case DeviceType.speaker:
        return '🔊';
      case DeviceType.heater:
        return '🔥';
      case DeviceType.custom:
        return '🏠';
    }
  }
}

class DeviceModel {
  final String id;       // relay1..relay10
  final String name;
  final bool state;      // on/off
  final DeviceType type;
  final String room;
  final bool favorite;
  final bool visible;
  final int position;
  final int colorValue;  // Color as int
  final String? customIcon;
  final DateTime? lastUpdated;

  const DeviceModel({
    required this.id,
    required this.name,
    required this.state,
    required this.type,
    required this.room,
    required this.favorite,
    required this.visible,
    required this.position,
    required this.colorValue,
    this.customIcon,
    this.lastUpdated,
  });

  /// Default list of 10 relay devices
  static List<DeviceModel> defaults() {
    const names = [
      'Living Room Light', 'Bedroom Light', 'Kitchen Light', 'Bathroom Light',
      'Garden Light', 'Fan', 'AC', 'Plug 1', 'Plug 2', 'Relay 10',
    ];
    const types = [
      DeviceType.bulb, DeviceType.bulb, DeviceType.bulb, DeviceType.bulb,
      DeviceType.bulb, DeviceType.fan, DeviceType.ac, DeviceType.plug,
      DeviceType.plug, DeviceType.custom,
    ];
    const rooms = [
      'Living Room', 'Bedroom', 'Kitchen', 'Bathroom',
      'Garden', 'Living Room', 'Bedroom', 'Kitchen',
      'Office', 'Custom',
    ];
    return List.generate(10, (i) => DeviceModel(
      id: 'relay${i + 1}',
      name: names[i],
      state: false,
      type: types[i],
      room: rooms[i],
      favorite: i < 3,
      visible: true,
      position: i,
      colorValue: 0xFF6C63FF,
    ));
  }

  factory DeviceModel.fromMap(Map<dynamic, dynamic> data, String id) {
    return DeviceModel(
      id: id,
      name: data['name'] ?? id,
      state: data['state'] == true || data['state'] == 1,
      type: DeviceType.values.firstWhere(
        (t) => t.name == (data['type'] ?? 'bulb'),
        orElse: () => DeviceType.bulb,
      ),
      room: data['room'] ?? 'Living Room',
      favorite: data['favorite'] ?? false,
      visible: data['visible'] ?? true,
      position: data['position'] ?? 0,
      colorValue: data['color'] ?? 0xFF6C63FF,
      customIcon: data['customIcon'],
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'state': state,
        'type': type.name,
        'room': room,
        'favorite': favorite,
        'visible': visible,
        'position': position,
        'color': colorValue,
        'customIcon': customIcon,
      };

  DeviceModel copyWith({
    String? name,
    bool? state,
    DeviceType? type,
    String? room,
    bool? favorite,
    bool? visible,
    int? position,
    int? colorValue,
    String? customIcon,
  }) {
    return DeviceModel(
      id: id,
      name: name ?? this.name,
      state: state ?? this.state,
      type: type ?? this.type,
      room: room ?? this.room,
      favorite: favorite ?? this.favorite,
      visible: visible ?? this.visible,
      position: position ?? this.position,
      colorValue: colorValue ?? this.colorValue,
      customIcon: customIcon ?? this.customIcon,
      lastUpdated: DateTime.now(),
    );
  }
}
