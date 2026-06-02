import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_colors.dart';

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

final darkThemeProvider = Provider<ThemeData>((ref) {
  return _buildDarkTheme();
});

final lightThemeProvider = Provider<ThemeData>((ref) {
  return _buildLightTheme();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const String _themeKey = 'theme_mode';
  late Box<String> _themeBox;

  ThemeModeNotifier() : super(ThemeMode.dark) {
    _initTheme();
  }

  Future<void> _initTheme() async {
    _themeBox = await Hive.openBox<String>('theme_prefs');
    final savedTheme = _themeBox.get(_themeKey, defaultValue: 'dark');
    state = _stringToThemeMode(savedTheme!);
  }

  Future<void> toggleTheme() async {
    final newMode = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    state = newMode;
    await _themeBox.put(_themeKey, _themeModeToString(newMode));
  }

  ThemeMode _stringToThemeMode(String value) {
    return value == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  String _themeModeToString(ThemeMode mode) {
    return mode == ThemeMode.light ? 'light' : 'dark';
  }
}

ThemeData _buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.deepSpaceBlack,
    primaryColor: AppColors.neonPurple,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.neonPurple,
      secondary: AppColors.neonCyan,
      surface: AppColors.deepSpaceBlackLight,
      error: AppColors.neonPink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.deepSpaceBlack,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
      bodyLarge: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
      ),
      bodyMedium: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 14,
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
  );
}

ThemeData _buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.cloudWhite,
    primaryColor: AppColors.neonPurple,
    colorScheme: const ColorScheme.light(
      primary: AppColors.neonPurple,
      secondary: AppColors.neonCyan,
      surface: AppColors.cloudWhiteLight,
      error: AppColors.neonPink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cloudWhite,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.deepSpaceBlack,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: AppColors.deepSpaceBlack,
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
      bodyLarge: TextStyle(
        color: AppColors.deepSpaceBlack,
        fontSize: 16,
      ),
      bodyMedium: TextStyle(
        color: Color(0xFF666666),
        fontSize: 14,
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.deepSpaceBlack),
  );
}
