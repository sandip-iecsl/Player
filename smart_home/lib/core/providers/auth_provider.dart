import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';
import '../services/firebase_service.dart';

// Current Firebase auth user
final firebaseUserProvider = StreamProvider((ref) =>
    FirebaseService.instance.authStateChanges);

// Full UserModel stream (refreshes on role/status changes in Firestore)
final userModelProvider = StreamProvider<UserModel?>((ref) {
  final uid = FirebaseService.instance.currentUid;
  if (uid == null) return const Stream.empty();
  return ref.watch(authRepositoryProvider).userStream(uid);
});

// Auth state controller
class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    final uid = FirebaseService.instance.currentUid;
    if (uid == null) return null;
    return FirebaseService.instance.fetchUser(uid);
  }

  Future<void> signIn(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signIn(email, password),
    );
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String phone,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).register(
            name: name, email: email, password: password, phone: phone),
    );
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(null);
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, UserModel?>(() => AuthNotifier());
