import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/authentication/presentation/screens/splash_screen.dart';
import '../../features/authentication/presentation/screens/login_screen.dart';
import '../../features/authentication/presentation/screens/signup_screen.dart';
import '../../features/authentication/presentation/screens/forgot_password_screen.dart';
import '../../features/authentication/presentation/screens/waiting_approval_screen.dart';
import '../../features/authentication/presentation/screens/account_disabled_screen.dart';
import '../../features/authentication/presentation/screens/no_internet_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/devices/presentation/screens/device_detail_screen.dart';
import '../../features/rooms/presentation/screens/rooms_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/admin/presentation/screens/admin_panel_screen.dart';
import '../../features/automation/presentation/screens/automation_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../models/device_model.dart';
import '../providers/auth_provider.dart';
import '../models/user_model.dart';

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';
  static const waitingApproval = '/waiting-approval';
  static const accountDisabled = '/account-disabled';
  static const noInternet = '/no-internet';
  static const dashboard = '/dashboard';
  static const deviceDetail = '/device-detail';
  static const rooms = '/rooms';
  static const settings = '/settings';
  static const profile = '/profile';
  static const admin = '/admin';
  static const automation = '/automation';
  static const notifications = '/notifications';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    redirect: (context, state) {
      final authAsync = ref.read(authNotifierProvider);
      return authAsync.when(
        loading: () => AppRoutes.splash,
        error: (_, __) => AppRoutes.login,
        data: (user) {
          final location = state.matchedLocation;
          final authPaths = [AppRoutes.login, AppRoutes.signup, AppRoutes.forgotPassword];
          if (user == null) {
            if (authPaths.contains(location)) return null;
            return AppRoutes.login;
          }
          if (user.isDisabled) return AppRoutes.accountDisabled;
          if (user.isPending) return AppRoutes.waitingApproval;
          if (authPaths.contains(location) || location == AppRoutes.splash) {
            return AppRoutes.dashboard;
          }
          return null;
        },
      );
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(path: AppRoutes.signup, builder: (_, __) => const SignupScreen()),
      GoRoute(path: AppRoutes.forgotPassword, builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: AppRoutes.waitingApproval, builder: (_, __) => const WaitingApprovalScreen()),
      GoRoute(path: AppRoutes.accountDisabled, builder: (_, __) => const AccountDisabledScreen()),
      GoRoute(path: AppRoutes.noInternet, builder: (_, __) => const NoInternetScreen()),
      GoRoute(path: AppRoutes.dashboard, builder: (_, __) => const DashboardScreen()),
      GoRoute(
        path: AppRoutes.deviceDetail,
        builder: (_, state) {
          final device = state.extra as DeviceModel;
          return DeviceDetailScreen(device: device);
        },
      ),
      GoRoute(path: AppRoutes.rooms, builder: (_, __) => const RoomsScreen()),
      GoRoute(path: AppRoutes.settings, builder: (_, __) => const SettingsScreen()),
      GoRoute(path: AppRoutes.profile, builder: (_, __) => const ProfileScreen()),
      GoRoute(path: AppRoutes.admin, builder: (_, __) => const AdminPanelScreen()),
      GoRoute(path: AppRoutes.automation, builder: (_, __) => const AutomationScreen()),
      GoRoute(path: AppRoutes.notifications, builder: (_, __) => const NotificationsScreen()),
    ],
  );
});
