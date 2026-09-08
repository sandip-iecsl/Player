import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/app_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/device_provider.dart';
import '../../../../shared/widgets/gradient_button.dart';

class WaitingApprovalScreen extends ConsumerWidget {
  const WaitingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen for approval in realtime
    ref.listen(userModelProvider, (_, next) {
      next.whenData((user) {
        if (user != null && user.approved && user.status == 'active') {
          context.go(AppRoutes.dashboard);
        }
      });
    });

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: AppColors.coolGradient,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.hourglass_top_rounded,
                    color: Colors.white, size: 56),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(begin: 1, end: 1.05, duration: 1500.ms)
                  .animate()
                  .scale(duration: 700.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 32),
              Text(
                'Waiting for Approval',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ).animate().fade(delay: 200.ms),
              const SizedBox(height: 14),
              Text(
                'Your account has been created and is pending admin approval. You\'ll be notified once approved.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ).animate().fade(delay: 300.ms),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.secondary),
                    ),
                  ),
                  SizedBox(width: 10),
                  Text('Checking approval status...',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ).animate().fade(delay: 500.ms),
              const SizedBox(height: 48),
              GradientButton(
                text: 'Sign Out',
                gradient: const LinearGradient(
                    colors: [Color(0xFF555555), Color(0xFF333333)]),
                onPressed: () async {
                  await ref.read(authNotifierProvider.notifier).signOut();
                  if (context.mounted) context.go(AppRoutes.login);
                },
              ).animate().fade(delay: 600.ms),
            ],
          ),
        ),
      ),
    );
  }
}
