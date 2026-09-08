import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class NeumorphicContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadiusGeometry? borderRadius;
  final Color? color;
  final BoxShape shape;
  final bool isPressed;

  const NeumorphicContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
    this.color,
    this.shape = BoxShape.rectangle,
    this.isPressed = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = color ?? AppColors.deepSpaceBlackLight; // Secondary Background
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: shape == BoxShape.circle ? null : (borderRadius ?? BorderRadius.circular(16)),
        shape: shape,
        boxShadow: isPressed
            ? [
                // Inset/pressed shadow equivalent (using outer shadows with negative spread for simplicity or just reduced outer shadow)
                const BoxShadow(
                  color: Color(0x1AFFFFFF),
                  offset: Offset(-1, -1),
                  blurRadius: 2,
                ),
                const BoxShadow(
                  color: Color(0x40000000),
                  offset: Offset(1, 1),
                  blurRadius: 2,
                ),
              ]
            : [
                // Top-left glow
                const BoxShadow(
                  color: Color(0x1AFFFFFF),
                  offset: Offset(-4, -4),
                  blurRadius: 10,
                ),
                // Bottom-right shadow
                const BoxShadow(
                  color: Color(0x40000000),
                  offset: Offset(4, 4),
                  blurRadius: 10,
                ),
              ],
      ),
      child: child,
    );
  }
}
