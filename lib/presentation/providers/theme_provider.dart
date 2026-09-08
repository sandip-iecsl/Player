import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_colors.dart';

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

final themeColorProvider =
    StateNotifierProvider<ThemeColorNotifier, String>((ref) {
  return ThemeColorNotifier();
});

final darkThemeProvider = Provider<ThemeData>((ref) {
  ref.watch(themeModeProvider);
  ref.watch(themeColorProvider);
  return _buildDarkTheme();
});

final lightThemeProvider = Provider<ThemeData>((ref) {
  ref.watch(themeModeProvider);
  ref.watch(themeColorProvider);
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
    _apply();
  }

  Future<void> toggleTheme() async {
    final newMode = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    state = newMode;
    await _themeBox.put(_themeKey, _themeModeToString(newMode));
    _apply();
  }

  void _apply() {
    final accent = _themeBox.get('theme_accent', defaultValue: 'pink')!;
    AppColors.applyTheme(isDark: state == ThemeMode.dark, accentName: accent);
  }

  ThemeMode _stringToThemeMode(String value) {
    return value == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  String _themeModeToString(ThemeMode mode) {
    return mode == ThemeMode.light ? 'light' : 'dark';
  }
}

class ThemeColorNotifier extends StateNotifier<String> {
  static const String _accentKey = 'theme_accent';
  late Box<String> _themeBox;

  ThemeColorNotifier() : super('pink') {
    _initTheme();
  }

  Future<void> _initTheme() async {
    _themeBox = await Hive.openBox<String>('theme_prefs');
    final savedAccent = _themeBox.get(_accentKey, defaultValue: 'pink');
    state = savedAccent!;
    _apply();
  }

  void _apply() {
    final isDark = _themeBox.get('theme_mode', defaultValue: 'dark') == 'dark';
    AppColors.applyTheme(isDark: isDark, accentName: state);
  }

  Future<void> setAccentColor(String name) async {
    state = name;
    await _themeBox.put(_accentKey, name);
    _apply();
  }
}

ThemeData _buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.deepSpaceBlack,
    primaryColor: AppColors.neonPink,
    colorScheme: ColorScheme.dark(
      primary: AppColors.neonPink,
      secondary: AppColors.neonCoral,
      surface: AppColors.deepSpaceBlackLight,
      error: AppColors.neonPink,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1E1E26),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0x2AFFFFFF)),
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 8,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.deepSpaceBlack,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: TextStyleTheme(
      AppColors.textPrimary,
      AppColors.textSecondary,
    ),
    iconTheme: IconThemeData(color: AppColors.textPrimary),
  );
}

ThemeData _buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.deepSpaceBlack, // AppColors.deepSpaceBlack mapped dynamically
    primaryColor: AppColors.neonPink,
    colorScheme: ColorScheme.light(
      primary: AppColors.neonPink,
      secondary: AppColors.neonCoral,
      surface: AppColors.deepSpaceBlackLight,
      error: AppColors.neonPink,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1E1E26),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0x2AFFFFFF)),
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 8,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.deepSpaceBlack,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: TextStyleTheme(
      AppColors.textPrimary,
      AppColors.textSecondary,
    ),
    iconTheme: IconThemeData(color: AppColors.textPrimary),
  );
}

// Helper TextTheme wrapper to avoid duplicate styling
TextTheme TextStyleTheme(Color primary, Color secondary) {
  return TextTheme(
    displayLarge: TextStyle(
      color: primary,
      fontSize: 32,
      fontWeight: FontWeight.bold,
    ),
    bodyLarge: TextStyle(
      color: primary,
      fontSize: 16,
    ),
    bodyMedium: TextStyle(
      color: secondary,
      fontSize: 14,
    ),
  );
}
