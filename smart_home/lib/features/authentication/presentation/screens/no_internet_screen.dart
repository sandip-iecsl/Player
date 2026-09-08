import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/app_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../shared/widgets/gradient_button.dart';

class NoInternetScreen extends ConsumerWidget {
  const NoInternetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    online.whenData((isOnline) {
      if (isOnline) context.go(AppRoutes.dashboard);
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
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.wifi_off_rounded,
                    color: AppColors.warning, size: 56),
              ).animate().scale(duration: 700.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 32),
              Text('No Internet',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center)
                  .animate().fade(delay: 200.ms),
              const SizedBox(height: 14),
              Text(
                'Please check your internet connection and try again.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ).animate().fade(delay: 300.ms),
              const SizedBox(height: 48),
              GradientButton(
                text: 'Retry',
                gradient: AppColors.warmGradient,
                icon: Icons.refresh_rounded,
                onPressed: () => context.go(AppRoutes.dashboard),
              ).animate().fade(delay: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}
