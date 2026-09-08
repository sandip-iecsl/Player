import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/app_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/device_provider.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../shared/widgets/status_badge.dart';

class DashboardHeader extends ConsumerWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userModelProvider);
    final onlineCount = ref.watch(onlineDeviceCountProvider);
    final isOnline = ref.watch(isOnlineProvider).value ?? true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              GestureDetector(
                onTap: () => context.push(AppRoutes.profile),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: userAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const Icon(Icons.person, color: Colors.white),
                    data: (user) {
                      if (user?.profileImage != null) {
                        return ClipOval(
                          child: Image.network(user!.profileImage!, fit: BoxFit.cover),
                        );
                      }
                      return Center(
                        child: Text(
                          (user?.name.isNotEmpty == true)
                              ? user!.name[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    userAsync.when(
                      loading: () => const SizedBox(height: 16, width: 120,
                          child: LinearProgressIndicator()),
                      error: (_, __) => const Text('Hello!'),
                      data: (user) => Text(
                        AppUtils.getGreeting(user?.name.split(' ').first ?? 'User'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                    Text(
                      '$onlineCount device${onlineCount != 1 ? 's' : ''} on',
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontFamily: 'Poppins'),
                    ),
                  ],
                ),
              ),
              // Status badges
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(label: 'WiFi', online: isOnline),
                  const SizedBox(height: 4),
                  StatusBadge(label: 'Firebase', online: isOnline),
                ],
              ),
              const SizedBox(width: 12),
              // Notifications
              IconButton(
                onPressed: () => context.push(AppRoutes.notifications),
                icon: const Icon(Icons.notifications_outlined),
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ],
      ),
    ).animate().fade(duration: 400.ms).slideY(begin: -0.1);
  }
}
