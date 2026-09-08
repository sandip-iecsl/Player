import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/local_chat_service.dart';
import '../../features/admin/engines/user_management_engine.dart';

class ManageUsersScreen extends StatefulWidget {
  final bool showAppBar;
  const ManageUsersScreen({super.key, this.showAppBar = true});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  final LocalChatService _chatService = LocalChatService();
  String? _myDeviceId;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadMyId();
  }

  Future<void> _loadMyId() async {
    final id = await _chatService.getDeviceId();
    setState(() {
      _myDeviceId = id;
    });
  }

  Color _getAvatarColor(String seed) {
    final colors = [
      const Color(0xFF00A884),
      const Color(0xFF1E88E5),
      const Color(0xFF8E24AA),
      const Color(0xFFD81B60),
      const Color(0xFFF4511E),
      const Color(0xFF43A047),
      const Color(0xFF00ACC1),
      const Color(0xFF3949AB),
    ];
    int hash = 0;
    for (int i = 0; i < seed.length; i++) {
      hash = seed.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return colors[hash.abs() % colors.length];
  }

  Future<void> _deleteUser(String uid, String name) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.deepSpaceBlackLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete User?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to permanently delete "$name"?\n\n'
          '• Firebase profile & history\n'
          '• Chat presence data\n'
          '• Pending delivery queues\n\n'
          'This action cannot be undone.',
          style: const TextStyle(color: Colors.grey, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete Permanently', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (_myDeviceId != null && uid == _myDeviceId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You cannot delete your own admin account.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      try {
        await UserManagementEngine().deleteUser(uid);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('User "$name" data completely wiped from database.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete user data: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mainContent = StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: AppColors.neonPink));
          }

          final docs = snapshot.data?.docs ?? [];
          final users = docs.map((doc) {
            final data = Map<String, dynamic>.from(doc.data() as Map);
            final uid = data['uid'] as String? ?? doc.id;
            final name = LocalChatService().resolveDisplayName(data, fallback: 'Unknown User');
            final status = data['status'] as String? ?? 'offline';
            final isAdminFlag = data['isAdmin'] == true;
            final role = isAdminFlag ? 'admin' : (data['role'] as String? ?? 'user');
            final lastActive = data['lastActive'] as Timestamp?;
            final createdAt = data['createdAt'] as Timestamp? ?? data['registrationDate'] as Timestamp?;
            final deviceInfo = (data['deviceInfo'] ?? data['device'] ?? data['deviceModel'] ?? '').toString();
            return {
              'uid': uid,
              'name': name,
              'status': status,
                'isAdmin': isAdminFlag,
              'role': role,
              'lastActive': lastActive,
              'createdAt': createdAt,
              'deviceInfo': deviceInfo,
              'data': data,
            };
          }).toList();

          final filteredUsers = users.where((user) {
            if (_searchQuery.isEmpty) return true;
            final haystack = [
              user['name'],
              user['uid'],
              user['role'],
            ].join(' ').toLowerCase();
            return haystack.contains(_searchQuery);
          }).toList()
            ..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));

          if (filteredUsers.isEmpty) {
            return const Center(
              child: Text('No matching users found.', style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.only(top: 8),
            itemCount: filteredUsers.length,
            separatorBuilder: (context, index) => const Padding(
              padding: EdgeInsets.only(left: 76),
              child: Divider(color: Colors.white10, height: 1),
            ),
            itemBuilder: (context, index) {
              final user = filteredUsers[index];
              final uid = user['uid'] as String;
              final name = user['name'] as String;
              final status = user['status'] as String;
              final role = user['role'] as String;
              final isAdminFlag = user['isAdmin'] as bool? ?? false;
              final lastActive = user['lastActive'] as Timestamp?;
              final createdAt = user['createdAt'] as Timestamp?;
              final deviceInfo = user['deviceInfo'] as String;
              final isMe = uid == _myDeviceId;
              final isOnline = status == 'online';
              final lastActiveText = lastActive != null ? '${lastActive.toDate().toLocal().toString().split('.').first}' : 'Not available';
              final createdText = createdAt != null ? '${createdAt.toDate().toLocal().toString().split('.').first}' : 'Not available';

              return Card(
                color: const Color(0xFF111111),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: _getAvatarColor(uid),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          if (isOnline)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF25D366),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black, width: 1.5),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    isMe ? '$name (You)' : name,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (isAdminFlag)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.neonPink.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text('Admin', style: TextStyle(color: AppColors.neonPink, fontSize: 11, fontWeight: FontWeight.bold)),
                                  )
                                else
                                  const SizedBox.shrink(),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                                  color: AppColors.deepSpaceBlackLight,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  onSelected: (value) async {
                                    if (value == 'delete') {
                                      _deleteUser(uid, name);
                                    } else if (value == 'toggle_admin') {
                                      try {
                                        await UserManagementEngine().setAdminFlag(uid, !isAdminFlag);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(!isAdminFlag ? 'Promoted $name to admin.' : 'Revoked admin from $name.'),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Failed to update admin flag: $e'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'toggle_admin',
                                      child: Row(
                                        children: [
                                          Icon(isAdminFlag ? Icons.remove_moderator_outlined : Icons.how_to_reg, color: isAdminFlag ? Colors.orange : Colors.green, size: 20),
                                          const SizedBox(width: 12),
                                          Text(isAdminFlag ? 'Revoke Admin' : 'Promote to Admin', style: TextStyle(color: isAdminFlag ? Colors.orange : Colors.green)),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                          SizedBox(width: 12),
                                          Text('Delete User', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(uid, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(isOnline ? Icons.circle : Icons.circle_outlined, color: isOnline ? const Color(0xFF25D366) : Colors.grey, size: 10),
                                const SizedBox(width: 6),
                                Text(isOnline ? 'Online' : 'Offline', style: TextStyle(color: isOnline ? const Color(0xFF25D366) : Colors.grey, fontSize: 12)),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(role.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('Last active: $lastActiveText', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text('Registered: $createdText', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            if (deviceInfo.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('Device: $deviceInfo', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

    if (!widget.showAppBar) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: mainContent,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Manage Users', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by name, uid, or role',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF171717),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
            ),
          ),
          Expanded(child: mainContent),
        ],
      ),
    );
  }
}
