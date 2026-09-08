import '../../features/admin/engines/user_management_engine.dart';
import '../../core/kernel/aura_application.dart';

class UserDomainService {
  static final UserDomainService _instance = UserDomainService._internal();
  factory UserDomainService() => _instance;
  UserDomainService._internal();

  /// Gets authenticated UID safely from Kernel.
  String getAuthenticatedUserId() {
    return AuraApplication().authenticatedUid;
  }

  /// Delete user from database directory.
  Future<void> wipeUserRecord(String uid) async {
    await UserManagementEngine().deleteUser(uid);
  }
}
