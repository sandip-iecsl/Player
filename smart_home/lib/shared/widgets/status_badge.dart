import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final bool online;
  final bool pulse;

  const StatusBadge({
    super.key,
    required this.label,
    required this.online,
    this.pulse = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.online : AppColors.offline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ).animate(onPlay: (c) => c.repeat())
            .scale(begin: const Offset(1, 1), end: const Offset(1.4, 1.4), duration: 600.ms)
            .then()
            .scale(begin: const Offset(1.4, 1.4), end: const Offset(1, 1), duration: 600.ms),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins')),
      ],
    );
  }
}
