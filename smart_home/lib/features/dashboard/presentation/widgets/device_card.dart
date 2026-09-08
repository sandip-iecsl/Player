import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/app_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/device_model.dart';
import '../../../../core/providers/device_provider.dart';

class DeviceCard extends ConsumerStatefulWidget {
  final DeviceModel device;
  final int index;

  const DeviceCard({super.key, required this.device, required this.index});

  @override
  ConsumerState<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends ConsumerState<DeviceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final isOn = device.state;
    final color = Color(device.colorValue);

    return GestureDetector(
      onTap: () => ref.read(deviceNotifierProvider.notifier).toggle(device),
      onLongPress: () => context.push(AppRoutes.deviceDetail, extra: device),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: isOn
              ? LinearGradient(
                  colors: [color, color.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    Theme.of(context).cardColor,
                    Theme.of(context).cardColor.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOn
                ? color.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.05),
            width: 1.5,
          ),
          boxShadow: isOn
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  )
                ]
              : [],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Device icon in circle
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isOn
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        device.customIcon ?? device.type.iconAsset,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                  // Power toggle
                  GestureDetector(
                    onTap: () =>
                        ref.read(deviceNotifierProvider.notifier).toggle(device),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isOn
                            ? Colors.white.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.07),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.power_settings_new_rounded,
                        size: 18,
                        color: isOn ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Animated dot for online status
              if (isOn)
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white
                              .withValues(alpha: 0.5 + _pulseCtrl.value * 0.5),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text('Active',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 10,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                )
              else
                Text('Inactive',
                    style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 10,
                        fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Text(
                device.name,
                style: TextStyle(
                  color: isOn ? Colors.white : Theme.of(context).textTheme.titleMedium?.color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                device.room,
                style: TextStyle(
                  color: isOn
                      ? Colors.white.withValues(alpha: 0.65)
                      : AppColors.textHint,
                  fontSize: 11,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
        ),
      )
          .animate(delay: (widget.index * 50).ms)
          .fade(duration: 400.ms)
          .scale(begin: const Offset(0.85, 0.85), duration: 400.ms, curve: Curves.easeOut),
    );
  }
}
