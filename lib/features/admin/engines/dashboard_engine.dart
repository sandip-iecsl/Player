import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';

class DashboardEngine {
  static final DashboardEngine _instance = DashboardEngine._internal();
  factory DashboardEngine() => _instance;
  DashboardEngine._internal();

  /// Retrieve the system statistics for the dashboard.
  Future<Map<String, dynamic>> loadDashboardStats() async {
    try {
      final usersSnap = await FirebaseFirestore.instance.collection('users').get();
      final chatsSnap = await FirebaseFirestore.instance
          .collection('direct_chats')
          .get();

      // Read from new Command Queue
      final syncQueueBox = await Hive.openBox<String>('command_sync_queue');

      final total = usersSnap.docs.length;
      int online = 0;
      for (final doc in usersSnap.docs) {
        final data = doc.data();
        if (data['status'] == 'online') online++;
      }

      return {
        'totalUsers': total,
        'onlineUsers': online,
        'activeChats': chatsSnap.docs.length,
        'syncQueue': syncQueueBox.length,
      };
    } catch (_) {
      return {
        'totalUsers': 0,
        'onlineUsers': 0,
        'activeChats': 0,
        'syncQueue': 0,
      };
    }
  }
}
