import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum AppThemeMode { dark, light, oled, blue, green, purple }

class AppTheme {
  AppTheme._();

  static ThemeData dark() => _buildTheme(
        brightness: Brightness.dark,
        background: AppColors.darkBg,
        surface: AppColors.darkSurface,
        card: AppColors.darkCard,
      );

  static ThemeData light() => _buildTheme(
        brightness: Brightness.light,
        background: AppColors.lightBg,
        surface: AppColors.lightSurface,
        card: AppColors.lightCard,
        textPrimary: const Color(0xFF1A1A2E),
        textSecondary: const Color(0xFF4A4A6A),
      );

  static ThemeData oled() => _buildTheme(
        brightness: Brightness.dark,
        background: AppColors.oledBg,
        surface: AppColors.oledSurface,
        card: AppColors.oledCard,
      );

  static ThemeData blue() => _buildTheme(
        brightness: Brightness.dark,
        background: const Color(0xFF041830),
        surface: const Color(0xFF062040),
        card: const Color(0xFF082850),
        accent: const Color(0xFF00B4D8),
      );

  static ThemeData green() => _buildTheme(
        brightness: Brightness.dark,
        background: const Color(0xFF041A10),
        surface: const Color(0xFF062215),
        card: const Color(0xFF082C1A),
        accent: const Color(0xFF00E676),
      );

  static ThemeData purple() => _buildTheme(
        brightness: Brightness.dark,
        background: const Color(0xFF120A30),
        surface: const Color(0xFF1A1040),
        card: const Color(0xFF221550),
        accent: const Color(0xFFB388FF),
      );

  static ThemeData getTheme(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return light();
      case AppThemeMode.oled:
        return oled();
      case AppThemeMode.blue:
        return blue();
      case AppThemeMode.green:
        return green();
      case AppThemeMode.purple:
        return purple();
      case AppThemeMode.dark:
      default:
        return dark();
    }
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color card,
    Color accent = AppColors.primary,
    Color textPrimary = AppColors.textPrimary,
    Color textSecondary = AppColors.textSecondary,
  }) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Poppins',
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: Colors.white,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        error: AppColors.error,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
      ),
      scaffoldBackgroundColor: background,
      cardColor: card,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkCardLight : AppColors.lightCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: TextStyle(color: textSecondary, fontFamily: 'Poppins'),
        labelStyle: TextStyle(color: textSecondary, fontFamily: 'Poppins'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(color: textPrimary, fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(color: textPrimary, fontFamily: 'Poppins', fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: textPrimary, fontFamily: 'Poppins', fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: textPrimary, fontFamily: 'Poppins', fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: textPrimary, fontFamily: 'Poppins'),
        bodyMedium: TextStyle(color: textSecondary, fontFamily: 'Poppins'),
        labelLarge: TextStyle(color: textPrimary, fontFamily: 'Poppins', fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: card,
        contentTextStyle: TextStyle(color: textPrimary, fontFamily: 'Poppins'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dividerColor: isDark ? Colors.white12 : Colors.black12,
      iconTheme: IconThemeData(color: textSecondary),
    );
  }
}
