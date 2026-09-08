import 'package:cloud_firestore/cloud_firestore.dart';

class ChatSecurityEngine {
  static final ChatSecurityEngine _instance = ChatSecurityEngine._internal();
  factory ChatSecurityEngine() => _instance;
  ChatSecurityEngine._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Validates a chat room's passcode.
  Future<bool> verifyRoomPasscode(String roomId, String enteredCode) async {
    try {
      final doc = await _firestore.collection('direct_chats').doc(roomId).get();
      if (!doc.exists) return false;

      final data = doc.data();
      final correctCode = data?['chatCode'] as String?;
      return correctCode == enteredCode;
    } catch (_) {
      return false;
    }
  }
}
