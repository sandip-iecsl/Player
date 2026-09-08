import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/repositories/auth_repository.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/gradient_button.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).resetPassword(_emailCtrl.text);
      setState(() => _sent = true);
    } catch (e) {
      if (mounted) AppUtils.showSnack(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _sent ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() => Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: AppColors.warmGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 36),
            ).animate().scale(duration: 500.ms),
            const SizedBox(height: 24),
            Text('Forgot Password?', style: Theme.of(context).textTheme.headlineMedium)
                .animate().fade(delay: 100.ms),
            const SizedBox(height: 8),
            Text(
              'Enter your email and we\'ll send you a reset link.',
              style: Theme.of(context).textTheme.bodyMedium,
            ).animate().fade(delay: 200.ms),
            const SizedBox(height: 32),
            AppTextField(
              label: 'Email',
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              validator: Validators.email,
              prefixIcon: const Icon(Icons.email_outlined),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _send(),
            ).animate().fade(delay: 300.ms).slideY(begin: 0.1),
            const SizedBox(height: 28),
            GradientButton(
              text: 'Send Reset Link',
              onPressed: _loading ? null : _send,
              isLoading: _loading,
              gradient: AppColors.warmGradient,
            ).animate().fade(delay: 400.ms),
          ],
        ),
      );

  Widget _buildSuccess() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 48),
          ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 24),
          Text('Email Sent!', style: Theme.of(context).textTheme.headlineMedium)
              .animate().fade(delay: 200.ms),
          const SizedBox(height: 12),
          Text(
            'Check your inbox for a password reset link.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ).animate().fade(delay: 300.ms),
          const SizedBox(height: 36),
          GradientButton(
            text: 'Back to Login',
            onPressed: () => context.pop(),
          ).animate().fade(delay: 400.ms),
        ],
      );
}
