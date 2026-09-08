import 'app_command.dart';
import 'chat_commands.dart';
import 'admin_commands.dart';

class AppCommandFactory {
  static AppCommand fromJson(Map<String, dynamic> json) {
    final String type = json['type'] as String;
    final String commandId = json['commandId'] as String;
    final DateTime timestamp = DateTime.parse(json['timestamp'] as String);
    final int retryCount = json['retryCount'] as int? ?? 0;
    final CommandPriority priority = CommandPriority.values[json['priority'] as int? ?? 1];
    final CommandStatus status = CommandStatus.values[json['status'] as int? ?? 0];
    final Map<String, dynamic> payload = Map<String, dynamic>.from(
      AppCommand.deserializeValue(json['payload'] as Map) as Map,
    );

    switch (type) {
      // Chat Commands
      case 'CreateMessageCommand':
        return CreateMessageCommand(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          payload: payload,
        );
      case 'UpdateMessageCommand':
        return UpdateMessageCommand(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          payload: payload,
        );
      case 'DeleteMessageCommand':
        return DeleteMessageCommand(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          payload: payload,
        );
      case 'CreateConversationCommand':
        return CreateConversationCommand(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          payload: payload,
        );
      case 'UpdatePresenceCommand':
        return UpdatePresenceCommand(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          payload: payload,
        );

      // Admin Commands
      case 'UpdateSettingsCommand':
        return UpdateSettingsCommand(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          payload: payload,
        );
      case 'TrainSearchRuleCommand':
        return TrainSearchRuleCommand(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          payload: payload,
        );
      case 'DeleteUserCommand':
        return DeleteUserCommand(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          payload: payload,
        );
      case 'ExportUsersCommand':
        return ExportUsersCommand(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          payload: payload,
        );
      case 'ImportSearchRulesCommand':
        return ImportSearchRulesCommand(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          payload: payload,
        );
      case 'CreateAuditLogCommand':
        return CreateAuditLogCommand(
          commandId: commandId,
          timestamp: timestamp,
          retryCount: retryCount,
          priority: priority,
          status: status,
          payload: payload,
        );

      default:
        throw Exception('Unknown AppCommand type: $type');
    }
  }
}
