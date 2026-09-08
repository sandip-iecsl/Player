import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/app_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../shared/widgets/gradient_button.dart';

class AccountDisabledScreen extends ConsumerWidget {
  const AccountDisabledScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  color: AppColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.block_rounded,
                    color: AppColors.error, size: 56),
              ).animate().scale(duration: 700.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 32),
              Text('Account Disabled',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center)
                  .animate().fade(delay: 200.ms),
              const SizedBox(height: 14),
              Text(
                'Your account has been disabled by an administrator. Please contact support for assistance.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ).animate().fade(delay: 300.ms),
              const SizedBox(height: 48),
              GradientButton(
                text: 'Sign Out',
                gradient: const LinearGradient(
                    colors: [AppColors.error, Color(0xFFB71C1C)]),
                onPressed: () async {
                  await ref.read(authNotifierProvider.notifier).signOut();
                  if (context.mounted) context.go(AppRoutes.login);
                },
              ).animate().fade(delay: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}
