import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final lockProvider = StateNotifierProvider<LockNotifier, LockState>((ref) {
  return LockNotifier();
});

class LockState {
  final bool isLocked;
  final bool isIncorrect;
  final DateTime? lastUnlocked;
  final String? userName;

  LockState({
    required this.isLocked,
    this.isIncorrect = false,
    this.lastUnlocked,
    this.userName,
  });

  LockState copyWith({
    bool? isLocked,
    bool? isIncorrect,
    DateTime? lastUnlocked,
    String? userName,
  }) {
    return LockState(
      isLocked: isLocked ?? this.isLocked,
      isIncorrect: isIncorrect ?? this.isIncorrect,
      lastUnlocked: lastUnlocked ?? this.lastUnlocked,
      userName: userName ?? this.userName,
    );
  }
}

class LockNotifier extends StateNotifier<LockState> {
  static const String _lockBoxName = 'settings';
  static const String _lastUnlockedKey = 'last_unlocked';

  // ==========================================
  // 🔒 APP PASSWORD SETTING
  // Change this value to update the app lock passcode!
  // ==========================================
  static const String _staticPassword = 'Sandip_XYZ-05';

  LockNotifier() : super(LockState(isLocked: true)) {
    _init();
  }

  Future<void> _init() async {
    final box = await Hive.openBox(_lockBoxName);
    final lastUnlockedStr = box.get(_lastUnlockedKey);
    final savedName = box.get('user_name'); // Fetch username

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
    );
  }

  void unlock(String password) async {
    if (password == _staticPassword) {
      final now = DateTime.now();
      final box = await Hive.openBox(_lockBoxName);
      await box.put(_lastUnlockedKey, now.toIso8601String());

      state = state.copyWith(
          isLocked: false, isIncorrect: false, lastUnlocked: now);
    } else {
      state = state.copyWith(isIncorrect: true);
    }
  }

  void resetIncorrect() {
    state = state.copyWith(isIncorrect: false);
  }

  Future<void> setUserName(String name) async {
    final box = await Hive.openBox(_lockBoxName);
    await box.put('user_name', name.trim());
    state = state.copyWith(userName: name.trim());
  }
}
