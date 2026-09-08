import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../../core/constants/app_colors.dart';

class ThemeSelectionDialog extends ConsumerWidget {
  const ThemeSelectionDialog({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const ThemeSelectionDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final activeAccent = ref.watch(themeColorProvider);
    final isDark = themeMode == ThemeMode.dark;

    final accents = [
      {'name': 'pink', 'label': 'Cyberpunk', 'color1': const Color(0xFFFF2A7A), 'color2': const Color(0xFFFF7E40)},
      {'name': 'purple', 'label': 'Amethyst', 'color1': const Color(0xFF9D4EDD), 'color2': const Color(0xFFE0AAFF)},
      {'name': 'emerald', 'label': 'Emerald', 'color1': const Color(0xFF00FF88), 'color2': const Color(0xFF00BFA5)},
      {'name': 'blue', 'label': 'Ocean', 'color1': const Color(0xFF00D9FF), 'color2': const Color(0xFF0055FF)},
      {'name': 'orange', 'label': 'Sunset', 'color1': const Color(0xFFFFAA00), 'color2': const Color(0xFFFF5500)},
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.deepSpaceBlackLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.neonPink.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonPink.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 5,
          )
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 4.5,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'App Customizer',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            'Choose your vibe and accent color',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),
          
          // Theme Mode Switcher
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dark Mode',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Switch(
                value: isDark,
                activeThumbColor: AppColors.neonPink,
                activeTrackColor: AppColors.neonPink.withOpacity(0.3),
                inactiveThumbColor: AppColors.textSecondary,
                inactiveTrackColor: AppColors.deepSpaceBlackLighter,
                onChanged: (_) {
                  ref.read(themeModeProvider.notifier).toggleTheme();
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Divider
          Divider(color: AppColors.divider.withOpacity(0.2), height: 1),
          const SizedBox(height: 24),
          
          // Accent Color Heading
          Text(
            'Accent Colors',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          
          // Color Selectors
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: accents.length,
              itemBuilder: (context, index) {
                final item = accents[index];
                final name = item['name'] as String;
                final label = item['label'] as String;
                final color1 = item['color1'] as Color;
                final color2 = item['color2'] as Color;
                final isSelected = activeAccent == name;

                return Padding(
                  padding: const EdgeInsets.only(right: 20.0),
                  child: GestureDetector(
                    onTap: () {
                      ref.read(themeColorProvider.notifier).setAccentColor(name);
                    },
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [color1, color2],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color1.withOpacity(isSelected ? 0.5 : 0.2),
                                blurRadius: isSelected ? 12 : 6,
                                spreadRadius: isSelected ? 1 : 0,
                                offset: const Offset(0, 3),
                              )
                            ],
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 24,
                                )
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          style: TextStyle(
                            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
