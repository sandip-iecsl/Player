import 'package:flutter/material.dart';

class AppColors {
  // Theme Backgrounds
  static Color deepSpaceBlack = const Color(0xFF1A0E17);
  static Color deepSpaceBlackLight = const Color(0xFF251622);
  static Color deepSpaceBlackLighter = const Color(0xFF332030);

  // Cloud White (Light Mode counterparts)
  static Color cloudWhite = const Color(0xFFFAFAFA);
  static Color cloudWhiteLight = const Color(0xFFF0F0F0);
  static Color cloudWhiteDark = const Color(0xFFE8E8E8);

  // Accent Colors
  static Color neonPurple = const Color(0xFF9D4EDD);
  static Color neonCyan = const Color(0xFF00D9FF);
  static Color neonPink = const Color(0xFFFF2A7A); // Primary Dynamic Accent
  static Color neonCoral = const Color(0xFFFF7E40); // Secondary Dynamic Accent
  static Color neonGreen = const Color(0xFF00FF41);

  // Neutral Text and Dividers
  static Color textPrimary = const Color(0xFFFFFFFF);
  static Color textSecondary = const Color(0xFF7D5C75);
  static Color divider = const Color(0xFF7D5C75);

  // Glassmorphism
  static Color glassLight = const Color(0x1AFFFFFF);
  static Color glassDark = const Color(0x1A000000);

  /// Apply central theme configuration to all color fields
  static void applyTheme({required bool isDark, required String accentName}) {
    // 1. Configure Background and Text Neutral colors
    if (isDark) {
      deepSpaceBlack = const Color(0xFF1A0E17);
      deepSpaceBlackLight = const Color(0xFF251622);
      deepSpaceBlackLighter = const Color(0xFF332030);
      textPrimary = const Color(0xFFFFFFFF);
      textSecondary = const Color(0xFF7D5C75);
      divider = const Color(0xFF7D5C75);
    } else {
      // Light Mode values
      deepSpaceBlack = const Color(0xFFFAFAFA);
      deepSpaceBlackLight = const Color(0xFFF0F0F0);
      deepSpaceBlackLighter = const Color(0xFFE8E8E8);
      textPrimary = const Color(0xFF1A0E17);
      textSecondary = const Color(0xFF6B5866);
      divider = const Color(0xFFD4C8D0);
    }

    // 2. Configure Dynamic Accent Colors
    switch (accentName.toLowerCase()) {
      case 'purple':
        neonPink = const Color(0xFF9D4EDD); // Electric Violet
        neonCoral = const Color(0xFFD81159); // Magenta
        break;
      case 'emerald':
        neonPink = const Color(0xFF00FF88); // Mint Green
        neonCoral = const Color(0xFF00BFA5); // Teal
        break;
      case 'blue':
        neonPink = const Color(0xFF00D9FF); // Cyan/Electric Blue
        neonCoral = const Color(0xFF0055FF); // Royal Blue
        break;
      case 'orange':
        neonPink = const Color(0xFFFFAA00); // Gold
        neonCoral = const Color(0xFFFF5500); // Sunset Orange
        break;
      case 'pink':
      default:
        neonPink = const Color(0xFFFF2A7A); // Cyberpunk Hot Pink
        neonCoral = const Color(0xFFFF7E40); // Coral
        break;
    }
  }
}
