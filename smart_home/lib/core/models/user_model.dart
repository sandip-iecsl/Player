import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final bool approved;
  final String role;
  final String? profileImage;
  final DateTime createdAt;
  final DateTime? lastLogin;
  final String status; // active, disabled, pending
  final String theme;
  final String language;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.approved,
    required this.role,
    this.profileImage,
    required this.createdAt,
    this.lastLogin,
    required this.status,
    required this.theme,
    required this.language,
  });

  bool get isAdmin => role == 'admin';
  bool get isPending => !approved || status == 'pending';
  bool get isDisabled => status == 'disabled';

  factory UserModel.fromFirestore(Map<String, dynamic> data, String uid) {
    return UserModel(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      approved: data['approved'] ?? false,
      role: data['role'] ?? 'user',
      profileImage: data['profileImage'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLogin: (data['lastLogin'] as Timestamp?)?.toDate(),
      status: data['status'] ?? 'pending',
      theme: data['theme'] ?? 'dark',
      language: data['language'] ?? 'en',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'name': name,
        'email': email,
        'phone': phone,
        'approved': approved,
        'role': role,
        'profileImage': profileImage,
        'createdAt': Timestamp.fromDate(createdAt),
        'lastLogin': lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
        'status': status,
        'theme': theme,
        'language': language,
      };

  UserModel copyWith({
    String? name,
    String? email,
    String? phone,
    bool? approved,
    String? role,
    String? profileImage,
    DateTime? lastLogin,
    String? status,
    String? theme,
    String? language,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      approved: approved ?? this.approved,
      role: role ?? this.role,
      profileImage: profileImage ?? this.profileImage,
      createdAt: createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      status: status ?? this.status,
      theme: theme ?? this.theme,
      language: language ?? this.language,
    );
  }
}
