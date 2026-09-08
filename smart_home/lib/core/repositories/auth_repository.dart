import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/firebase_service.dart';
import '../constants/app_constants.dart';

class AuthRepository {
  final _fs = FirebaseService.instance;

  Future<UserModel> signIn(String email, String password) async {
    final cred = await _fs.signIn(email, password);
    final uid = cred.user!.uid;
    // Update lastLogin
    await _fs.updateUser(uid, {'lastLogin': DateTime.now().toIso8601String()});
    final user = await _fs.fetchUser(uid);
    if (user == null) throw Exception('User profile not found');
    return user;
  }

  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
    required String phone,
  }) async {
    final cred = await _fs.register(email, password);
    final uid = cred.user!.uid;
    final user = UserModel(
      uid: uid,
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      approved: false,
      role: AppConstants.roleUser,
      createdAt: DateTime.now(),
      status: AppConstants.statusPending,
      theme: 'dark',
      language: 'en',
    );
    await _fs.createUser(user);
    return user;
  }

  Future<void> signOut() => _fs.signOut();

  Future<void> resetPassword(String email) => _fs.sendPasswordReset(email);

  Stream<User?> get authStateChanges => _fs.authStateChanges;

  Stream<UserModel?> userStream(String uid) => _fs.userStream(uid);

  Future<UserModel?> fetchUser(String uid) => _fs.fetchUser(uid);

  Future<bool> isAdmin(String uid) => _fs.isAdmin(uid);
}

final authRepositoryProvider = Provider<AuthRepository>(_=> AuthRepository());
