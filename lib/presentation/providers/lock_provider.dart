import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/local_chat_service.dart';
import '../../data/services/user_registration_service.dart';
import '../../features/admin/engines/security_engine.dart';

final lockProvider = StateNotifierProvider<LockNotifier, LockState>((ref) {
  return LockNotifier();
});

class LockState {
  final bool isLocked;
  final bool isIncorrect;
  final DateTime? lastUnlocked;
  final String? userName;
  final bool isInitialized;

  LockState({
    required this.isLocked,
    this.isIncorrect = false,
    this.lastUnlocked,
    this.userName,
    this.isInitialized = false,
  });

  LockState copyWith({
    bool? isLocked,
    bool? isIncorrect,
    DateTime? lastUnlocked,
    String? userName,
    bool? isInitialized,
  }) {
    return LockState(
      isLocked: isLocked ?? this.isLocked,
      isIncorrect: isIncorrect ?? this.isIncorrect,
      lastUnlocked: lastUnlocked ?? this.lastUnlocked,
      userName: userName ?? this.userName,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

class LockNotifier extends StateNotifier<LockState> {
  static const String _lastUnlockedKey = 'last_unlocked';

  LockNotifier() : super(LockState(isLocked: true, isInitialized: false)) {
    _init();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUnlockedStr = prefs.getString(_lastUnlockedKey);
      String? savedName = prefs.getString('user_name');

      if ((savedName == null || savedName.trim().isEmpty)) {
        final profileBox = await Hive.openBox<String>('user_profile_cache');
        savedName = profileBox.get('current_user_name');
      }

      DateTime? lastUnlocked;
      bool isLocked = true;

      if (lastUnlockedStr != null) {
        lastUnlocked = DateTime.parse(lastUnlockedStr);
        final now = DateTime.now();

        // If unlocked less than 30 days ago, auto-unlock
        if (now.difference(lastUnlocked).inDays < 30) {
          isLocked = false;
        }
      }

      state = state.copyWith(
        isLocked: isLocked,
        lastUnlocked: lastUnlocked,
        userName: savedName,
        isInitialized: true,
      );
    } catch (e) {
      print('[LockProvider] Error loading user settings: $e');
      state = state.copyWith(isInitialized: true);
    }
  }

  void unlock(String password) async {
    try {
      // Always validate directly against Firestore — no hardcoded fallback
      final isValid = await SecurityEngine().validateAppLockPasscode(password);
      if (isValid) {
        final now = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastUnlockedKey, now.toIso8601String());
        state = state.copyWith(isLocked: false, isIncorrect: false, lastUnlocked: now);
      } else {
        state = state.copyWith(isIncorrect: true);
      }
    } catch (e) {
      debugPrint('[LockProvider] Error on unlock: $e');
      state = state.copyWith(isIncorrect: true);
    }
  }

  void resetIncorrect() {
    state = state.copyWith(isIncorrect: false);
  }

  Future<void> setUserName(String name) async {
    final normalizedName = name.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', normalizedName);
      await prefs.setBool('display_name_registered', normalizedName.isNotEmpty);

      final profileBox = await Hive.openBox<String>('user_profile_cache');
      await profileBox.put('current_user_name', normalizedName);
    } catch (e) {
      debugPrint('[LockProvider] Error saving username: $e');
    }

    // Full registration — writes to both Firestore DBs with all fields
    if (normalizedName.isNotEmpty) {
      await UserRegistrationService().registerOrUpdate(normalizedName);
    }

    state = state.copyWith(userName: normalizedName.isEmpty ? null : normalizedName);
  }
}
