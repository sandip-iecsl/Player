import 'package:cloud_firestore/cloud_firestore.dart';

class RoomModel {
  final String id;
  final String name;
  final int colorValue;
  final String icon;
  final int order;
  final DateTime? createdAt;

  const RoomModel({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.icon,
    required this.order,
    this.createdAt,
  });

  static List<RoomModel> defaults() => [
    const RoomModel(id: 'living_room', name: 'Living Room', colorValue: 0xFF6C63FF, icon: '🛋️', order: 0),
    const RoomModel(id: 'bedroom', name: 'Bedroom', colorValue: 0xFF3B82F6, icon: '🛏️', order: 1),
    const RoomModel(id: 'kitchen', name: 'Kitchen', colorValue: 0xFFFF6584, icon: '🍳', order: 2),
    const RoomModel(id: 'bathroom', name: 'Bathroom', colorValue: 0xFF00D9FF, icon: '🚿', order: 3),
    const RoomModel(id: 'garden', name: 'Garden', colorValue: 0xFF00E676, icon: '🌿', order: 4),
    const RoomModel(id: 'office', name: 'Office', colorValue: 0xFFFFD600, icon: '💼', order: 5),
  ];

  factory RoomModel.fromFirestore(Map<String, dynamic> data, String id) => RoomModel(
    id: id,
    name: data['name'] ?? '',
    colorValue: data['color'] ?? 0xFF6C63FF,
    icon: data['icon'] ?? '🏠',
    order: data['order'] ?? 0,
    createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
  );

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'color': colorValue,
    'icon': icon,
    'order': order,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
  };

  RoomModel copyWith({String? name, int? colorValue, String? icon, int? order}) => RoomModel(
    id: id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    icon: icon ?? this.icon,
    order: order ?? this.order,
    createdAt: createdAt,
  );
}
