import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/room_model.dart';

class RoomFilterBar extends StatelessWidget {
  final String selected;
  final List<RoomModel> rooms;
  final ValueChanged<String> onSelected;

  const RoomFilterBar({
    super.key,
    required this.selected,
    required this.rooms,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final allRooms = [
      const RoomModel(
          id: 'All', name: 'All', colorValue: 0xFF6C63FF, icon: '🏠', order: -1),
      ...rooms,
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: allRooms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final room = allRooms[i];
          final isSelected = selected == room.name;
          final color = Color(room.colorValue);
          return GestureDetector(
            onTap: () => onSelected(room.name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [color, color.withValues(alpha: 0.7)])
                    : null,
                color: isSelected
                    ? null
                    : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.08),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(room.icon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    room.name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
          ).animate(delay: (i * 40).ms).fade().slideX(begin: 0.1);
        },
      ),
    );
  }
}
