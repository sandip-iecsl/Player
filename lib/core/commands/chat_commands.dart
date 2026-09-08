import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_command.dart';

class CreateMessageCommand extends AppCommand {
  CreateMessageCommand({
    required String commandId,
    required DateTime timestamp,
    int retryCount = 0,
    CommandPriority priority = CommandPriority.medium,
    CommandStatus status = CommandStatus.pending,
    required Map<String, dynamic> payload,
  }) : super(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          type: 'CreateMessageCommand',
          payload: payload,
        );

  @override
  Future<bool> execute() async {
    try {
      final roomId = payload['roomId'] as String;
      final messageId = payload['messageId'] as String;
      final messageData = Map<String, dynamic>.from(payload['messageData'] as Map);

      // Convert the JSON-safe string timestamp back to a Firestore Timestamp
      if (messageData['timestamp'] is String) {
        final parsed = DateTime.tryParse(messageData['timestamp'] as String);
        if (parsed != null) {
          messageData['timestamp'] = Timestamp.fromDate(parsed);
        }
      }

      await FirebaseFirestore.instance
          .collection('direct_chats')
          .doc(roomId)
          .collection('messages')
          .doc(messageId)
          .set(messageData)
          .timeout(const Duration(seconds: 8));

      return true;
    } catch (e) {
      return false;
    }
  }
}

class UpdateMessageCommand extends AppCommand {
  UpdateMessageCommand({
    required String commandId,
    required DateTime timestamp,
    int retryCount = 0,
    CommandPriority priority = CommandPriority.medium,
    CommandStatus status = CommandStatus.pending,
    required Map<String, dynamic> payload,
  }) : super(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          type: 'UpdateMessageCommand',
          payload: payload,
        );

  @override
  Future<bool> execute() async {
    try {
      final roomId = payload['roomId'] as String;
      final messageId = payload['messageId'] as String;
      final updateData = payload['updateData'] as Map<String, dynamic>;

      await FirebaseFirestore.instance
          .collection('direct_chats')
          .doc(roomId)
          .collection('messages')
          .doc(messageId)
          .update(updateData)
          .timeout(const Duration(seconds: 8));

      return true;
    } catch (e) {
      return false;
    }
  }
}

class DeleteMessageCommand extends AppCommand {
  DeleteMessageCommand({
    required String commandId,
    required DateTime timestamp,
    int retryCount = 0,
    CommandPriority priority = CommandPriority.medium,
    CommandStatus status = CommandStatus.pending,
    required Map<String, dynamic> payload,
  }) : super(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          type: 'DeleteMessageCommand',
          payload: payload,
        );

  @override
  Future<bool> execute() async {
    try {
      final roomId = payload['roomId'] as String;
      final messageId = payload['messageId'] as String;
      final updateData = payload['updateData'] as Map<String, dynamic>;

      // Soft delete: updates specific fields like deletedForEveryone and text
      await FirebaseFirestore.instance
          .collection('direct_chats')
          .doc(roomId)
          .collection('messages')
          .doc(messageId)
          .update(updateData)
          .timeout(const Duration(seconds: 8));

      return true;
    } catch (e) {
      return false;
    }
  }
}

class CreateConversationCommand extends AppCommand {
  CreateConversationCommand({
    required String commandId,
    required DateTime timestamp,
    int retryCount = 0,
    CommandPriority priority = CommandPriority.medium,
    CommandStatus status = CommandStatus.pending,
    required Map<String, dynamic> payload,
  }) : super(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          type: 'CreateConversationCommand',
          payload: payload,
        );

  @override
  Future<bool> execute() async {
    try {
      final roomId = payload['roomId'] as String;
      final roomData = payload['roomData'] as Map<String, dynamic>;

      await FirebaseFirestore.instance
          .collection('direct_chats')
          .doc(roomId)
          .set(roomData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));

      return true;
    } catch (e) {
      return false;
    }
  }
}

class UpdatePresenceCommand extends AppCommand {
  UpdatePresenceCommand({
    required String commandId,
    required DateTime timestamp,
    int retryCount = 0,
    CommandPriority priority = CommandPriority.high,
    CommandStatus status = CommandStatus.pending,
    required Map<String, dynamic> payload,
  }) : super(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          type: 'UpdatePresenceCommand',
          payload: payload,
        );

  @override
  Future<bool> execute() async {
    try {
      final userId = payload['userId'] as String;
      final presenceData = payload['presenceData'] as Map<String, dynamic>;

      await FirebaseFirestore.instance
          .collection('live_users')
          .doc(userId)
          .set(presenceData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));

      return true;
    } catch (e) {
      return false;
    }
  }
}
