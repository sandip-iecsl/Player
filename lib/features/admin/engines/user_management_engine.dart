import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/commands/admin_commands.dart';
import '../../../core/kernel/aura_application.dart';
import '../../../core/sync/adaptive_sync_engine.dart';
import '../../../core/events/event_dispatcher.dart';
import '../../../core/events/admin_events.dart';
import '../../../core/transaction/transaction_manager.dart';
import '../../../core/shared/recovery/recovery_manager.dart';

class UserManagementEngine {
  static final UserManagementEngine _instance = UserManagementEngine._internal();
  factory UserManagementEngine() => _instance;
  UserManagementEngine._internal();

  /// Watch registered users stream.
  Stream<QuerySnapshot> watchUsers() {
    return FirebaseFirestore.instance.collection('users').snapshots();
  }

  /// Triggers user data wipe via command queue.
  Future<void> deleteUser(String userId) async {
    final currentUserId = AuraApplication().authenticatedUid;
    if (userId == currentUserId) {
      throw Exception('Cannot delete the currently authenticated admin user.');
    }

    await RecoveryManager().runRecoveryChecks();

    final commandId = 'deluser_${DateTime.now().millisecondsSinceEpoch}_$userId';
    final command = DeleteUserCommand(
      commandId: commandId,
      timestamp: DateTime.now(),
      payload: {'userId': userId},
    );

    final executedImmediately = await command.execute();
    if (executedImmediately) {
      EventDispatcher().publish(UserDeletedEvent(
        eventId: commandId,
        timestamp: DateTime.now(),
        userId: userId,
      ));
      return;
    }

    TransactionManager().beginTransaction();
    TransactionManager().addStep(TransactionStep(
      id: 'delete_user_command',
      execute: () async => AdaptiveSyncEngine().enqueue(command),
      rollback: () async {},
    ));
    final committed = await TransactionManager().commit();
    if (!committed) {
      throw Exception('User deletion transaction failed');
    }

    await AdaptiveSyncEngine().forceSync();

    EventDispatcher().publish(UserDeletedEvent(
      eventId: commandId,
      timestamp: DateTime.now(),
      userId: userId,
    ));
  }

  /// Set or unset the `isAdmin` flag on a user document.
  Future<void> setAdminFlag(String userId, bool makeAdmin) async {
    final currentUserId = AuraApplication().authenticatedUid;
    if (userId == currentUserId) {
      throw Exception('Cannot change admin flag on the currently authenticated user.');
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'isAdmin': makeAdmin,
      }, SetOptions(merge: true));

      EventDispatcher().publish(UserDeletedEvent(
        eventId: 'admin_flag_${DateTime.now().millisecondsSinceEpoch}_$userId',
        timestamp: DateTime.now(),
        userId: userId,
      ));
    } catch (e) {
      throw Exception('Failed to set admin flag: $e');
    }
  }
}
