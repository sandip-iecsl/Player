import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/app_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/repositories/device_repository.dart';
import '../../../../core/repositories/room_repository.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Load theme preference
    await ref.read(themeProvider.notifier).load();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    _navigate();
  }

  void _navigate() {
    final auth = ref.read(authNotifierProvider);
    auth.when(
      loading: () {},
      error: (_, __) => context.go(AppRoutes.login),
      data: (user) {
        if (user == null) {
          context.go(AppRoutes.login);
        } else if (user.isDisabled) {
          context.go(AppRoutes.accountDisabled);
        } else if (user.isPending) {
          context.go(AppRoutes.waitingApproval);
        } else {
          context.go(AppRoutes.dashboard);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(Icons.home_rounded, color: Colors.white, size: 56),
            )
                .animate()
                .scale(duration: 800.ms, curve: Curves.easeOutBack)
                .fade(duration: 600.ms),
            const SizedBox(height: 24),
            const Text(
              'Smart Home',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                fontFamily: 'Poppins',
              ),
            ).animate().fade(delay: 300.ms, duration: 600.ms).slideY(begin: 0.2),
            const SizedBox(height: 8),
            Text(
              'Control Your World',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                fontFamily: 'Poppins',
              ),
            ).animate().fade(delay: 500.ms, duration: 600.ms),
            const SizedBox(height: 60),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
              strokeWidth: 2.5,
            ).animate().fade(delay: 1000.ms),
          ],
        ),
      ),
    );
  }
}
