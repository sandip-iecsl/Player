import '../../features/chat/engines/conversation_engine.dart';
import '../../features/chat/engines/message_engine.dart';

class ConversationDomainService {
  static final ConversationDomainService _instance = ConversationDomainService._internal();
  factory ConversationDomainService() => _instance;
  ConversationDomainService._internal();

  /// Validates passcode and completes room handshake verification.
  Future<bool> verifyAndJoinRoom(String roomId, String enteredCode, String actualCode) async {
    if (enteredCode.trim().isEmpty || actualCode.trim().isEmpty) return false;
    
    if (enteredCode == actualCode) {
      await ConversationEngine().verifyRoom(roomId);
      return true;
    }
    return false;
  }

  /// Request room archiving.
  Future<void> archiveConversationRoom(String roomId) async {
    await MessageEngine().pruneExpiredMessages(roomId);
  }
}
