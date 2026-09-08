import 'package:cloud_firestore/cloud_firestore.dart';

class AdminConfigModel {
  final int configVersion;
  final DateTime updatedAt;
  final String updatedBy;
  final String checksum;
  final String creatorName;
  final String contactNumber;
  final String linkedinUrl;
  final bool showContact;
  final bool showLinkedin;
  final String adminPasscode;
  final String appLockPasscode;
  final String secretConsolePasscode;
  final int chatExpiryHours;

  AdminConfigModel({
    required this.configVersion,
    required this.updatedAt,
    required this.updatedBy,
    required this.checksum,
    required this.creatorName,
    required this.contactNumber,
    required this.linkedinUrl,
    required this.showContact,
    required this.showLinkedin,
    required this.adminPasscode,
    required this.appLockPasscode,
    required this.secretConsolePasscode,
    required this.chatExpiryHours,
  });

  Map<String, dynamic> toJson() => {
    'configVersion': configVersion,
    'updatedAt': Timestamp.fromDate(updatedAt),
    'updatedBy': updatedBy,
    'checksum': checksum,
    'creatorName': creatorName,
    'contactNumber': contactNumber,
    'linkedinUrl': linkedinUrl,
    'showContact': showContact,
    'showLinkedin': showLinkedin,
    'adminPasscode': adminPasscode,
    'appLockPasscode': appLockPasscode,
    'secretConsolePasscode': secretConsolePasscode,
    'chatExpiryHours': chatExpiryHours,
  };

  factory AdminConfigModel.fromJson(Map<String, dynamic> json) => AdminConfigModel(
    configVersion: (json['configVersion'] as num?)?.toInt() ?? 1,
    updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    updatedBy: json['updatedBy'] ?? '',
    checksum: json['checksum'] ?? '',
    creatorName: json['creatorName'] ?? 'Sandip',
    contactNumber: json['contactNumber'] ?? '8972966158',
    linkedinUrl: json['linkedinUrl'] ?? 'https://www.linkedin.com/in/sandipan-bhunia/',
    showContact: json['showContact'] ?? true,
    showLinkedin: json['showLinkedin'] ?? true,
    // Passcodes default to empty string — never a hardcoded password
    adminPasscode: json['adminPasscode']?.toString() ?? json['password']?.toString() ?? '',
    appLockPasscode: json['appLockPasscode']?.toString() ?? '',
    secretConsolePasscode: json['secretConsolePasscode']?.toString() ?? '',
    chatExpiryHours: (json['chatExpiryHours'] as num?)?.toInt() ?? 24,
  );
}
