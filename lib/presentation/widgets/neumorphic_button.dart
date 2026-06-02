import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class NeumorphicButton extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final double size;
  final Color? color;

  const NeumorphicButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.size = 50,
    this.color,
  });

  @override
  State<NeumorphicButton> createState() => _NeumorphicButtonState();
}

class _NeumorphicButtonState extends State<NeumorphicButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? AppColors.deepSpaceBlackLight : AppColors.cloudWhiteLight;
    final shadowColor = isDark ? Colors.black : Colors.grey.shade300;
    final highlightColor =
        isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(widget.size / 2),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: shadowColor.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(2, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: shadowColor.withOpacity(0.5),
                    blurRadius: 12,
                    offset: const Offset(4, 4),
                  ),
                  BoxShadow(
                    color: highlightColor,
                    blurRadius: 12,
                    offset: const Offset(-4, -4),
                  ),
                ],
        ),
        child: Icon(
          widget.icon,
          color: widget.color ??
              (isDark ? AppColors.neonPurple : AppColors.deepSpaceBlack),
          size: widget.size * 0.5,
        ),
      ),
    );
  }
}
