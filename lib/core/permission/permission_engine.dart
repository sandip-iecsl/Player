import 'package:flutter/widgets.dart';
import '../kernel/i_engine.dart';

enum UserRole { superAdmin, admin, moderator, developer, readOnly }

class PermissionEngine implements IEngine {
  static final PermissionEngine _instance = PermissionEngine._internal();
  factory PermissionEngine() => _instance;
  PermissionEngine._internal();

  UserRole _currentUserRole = UserRole.readOnly;

  // central capability definitions mapping roles to permitted actions
  final Map<UserRole, List<String>> _roleCapabilities = {
    UserRole.superAdmin: [
      'wipe_database',
      'train_ml_synonyms',
      'change_config_settings',
      'read_audit_logs',
      'access_developer_metrics',
    ],
    UserRole.admin: [
      'train_ml_synonyms',
      'change_config_settings',
      'read_audit_logs',
    ],
    UserRole.moderator: [
      'train_ml_synonyms',
      'read_audit_logs',
    ],
    UserRole.developer: [
      'read_audit_logs',
      'access_developer_metrics',
    ],
    UserRole.readOnly: [
      'read_audit_logs', // public logs only
    ],
  };

  @override
  Future<void> initialize() async {
    debugPrint('[PermissionEngine] 🛡️ Permission verification matrix initialized.');
  }

  @override
  Future<void> start() async {}

  /// Set the user's role during session initialization.
  void setUserRole(UserRole role) {
    _currentUserRole = role;
    debugPrint('[PermissionEngine] 🛡️ Current user role updated: $role');
  }

  /// Verifies if user holds permissions to execute action.
  bool hasPermission(String action) {
    final permissions = _roleCapabilities[_currentUserRole];
    if (permissions != null && permissions.contains(action)) {
      return true;
    }
    return false;
  }

  UserRole get currentUserRole => _currentUserRole;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
