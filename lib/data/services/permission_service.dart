import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class PermissionService {
  static Future<bool> requestNotificationPermission() async {
    try {
      // For Android 13+ (API 33+), we need to request notification permission
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.notification.request();
        debugPrint('[Permissions] Notification permission: $status');
        return status.isGranted;
      }
      return true; // iOS handles this automatically
    } catch (e) {
      debugPrint('[Permissions] Error requesting notification permission: $e');
      return false;
    }
  }

  static Future<bool> requestAudioPermissions() async {
    try {
      final permissions = <Permission>[
        Permission.notification,
        Permission.microphone,
      ];

      // Request all permissions
      final statuses = await permissions.request();
      
      // Check if all permissions are granted
      final allGranted = statuses.values.every((status) => status.isGranted);
      
      debugPrint('[Permissions] Audio permissions granted: $allGranted');
      debugPrint('[Permissions] Individual statuses: $statuses');
      
      return allGranted;
    } catch (e) {
      debugPrint('[Permissions] Error requesting audio permissions: $e');
      return false;
    }
  }

  static Future<bool> checkNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      debugPrint('[Permissions] Error checking notification permission: $e');
      return false;
    }
  }
}