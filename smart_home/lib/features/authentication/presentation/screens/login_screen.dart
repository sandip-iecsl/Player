import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/app_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/gradient_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _rememberMe = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConstants.kRememberMe) == true) {
      _emailCtrl.text = prefs.getString(AppConstants.kUserEmail) ?? '';
      setState(() => _rememberMe = true);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final notifier = ref.read(authNotifierProvider.notifier);
      await notifier.signIn(_emailCtrl.text, _passCtrl.text);
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setBool(AppConstants.kRememberMe, true);
        await prefs.setString(AppConstants.kUserEmail, _emailCtrl.text.trim());
      } else {
        await prefs.remove(AppConstants.kRememberMe);
        await prefs.remove(AppConstants.kUserEmail);
      }
      final auth = ref.read(authNotifierProvider);
      if (!mounted) return;
      auth.when(
        loading: () {},
        error: (e, _) => AppUtils.showSnack(context, e.toString(), isError: true),
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
    } catch (e) {
      if (mounted) AppUtils.showSnack(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                // Logo
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.home_rounded, color: Colors.white, size: 40),
                  ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
                ),
                const SizedBox(height: 32),
                Text(
                  'Welcome Back!',
                  style: Theme.of(context).textTheme.headlineMedium,
                ).animate().fade(delay: 100.ms).slideX(begin: -0.1),
                const SizedBox(height: 8),
                Text(
                  'Login to control your smart home',
                  style: Theme.of(context).textTheme.bodyMedium,
                ).animate().fade(delay: 200.ms),
                const SizedBox(height: 36),
                AppTextField(
                  label: 'Email',
                  hint: 'you@example.com',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: Validators.email,
                  prefixIcon: const Icon(Icons.email_outlined),
                ).animate().fade(delay: 300.ms).slideY(begin: 0.1),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Password',
                  controller: _passCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  validator: Validators.password,
                  prefixIcon: const Icon(Icons.lock_outline),
                ).animate().fade(delay: 400.ms).slideY(begin: 0.1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged: (v) => setState(() => _rememberMe = v ?? false),
                      activeColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    const Text('Remember me'),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.push(AppRoutes.forgotPassword),
                      child: const Text('Forgot Password?'),
                    ),
                  ],
                ).animate().fade(delay: 450.ms),
                const SizedBox(height: 28),
                GradientButton(
                  text: 'Login',
                  onPressed: _loading ? null : _login,
                  isLoading: _loading,
                ).animate().fade(delay: 500.ms).slideY(begin: 0.2),
                const SizedBox(height: 24),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Don't have an account?",
                          style: Theme.of(context).textTheme.bodyMedium),
                      TextButton(
                        onPressed: () => context.push(AppRoutes.signup),
                        child: const Text('Sign Up'),
                      ),
                    ],
                  ),
                ).animate().fade(delay: 600.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
