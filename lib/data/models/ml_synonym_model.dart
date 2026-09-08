import 'package:cloud_firestore/cloud_firestore.dart';

class MLSynonymModel {
  final String alias;
  final String target;
  final String category;
  final double weight;
  final int frequency;
  final DateTime updatedAt;
  final int version;

  MLSynonymModel({
    required this.alias,
    required this.target,
    required this.category,
    required this.weight,
    required this.frequency,
    required this.updatedAt,
    required this.version,
  });

  Map<String, dynamic> toJson() => {
    'alias': alias,
    'target': target,
    'category': category,
    'weight': weight,
    'frequency': frequency,
    'updatedAt': Timestamp.fromDate(updatedAt),
    'version': version,
  };

  factory MLSynonymModel.fromJson(Map<String, dynamic> json) => MLSynonymModel(
    alias: json['alias'] ?? '',
    target: json['target'] ?? '',
    category: json['category'] ?? 'general',
    weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
    frequency: (json['frequency'] as num?)?.toInt() ?? 0,
    updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    version: (json['version'] as num?)?.toInt() ?? 1,
  );
}
