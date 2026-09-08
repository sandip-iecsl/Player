import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/local_chat_service.dart';
import '../providers/audio_provider.dart';
import 'chat_room_screen.dart';
import 'secret_configuration_screen.dart';

class SecretConsoleScreen extends StatefulWidget {
  const SecretConsoleScreen({super.key});

  @override
  State<SecretConsoleScreen> createState() => _SecretConsoleScreenState();
}

class _SecretConsoleScreenState extends State<SecretConsoleScreen> {
  SharedPreferences? _prefs;
  bool _isLoading = true;
  final _chatService = LocalChatService();
  String? _myDeviceId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _myDeviceId = await _chatService.getDeviceId();

      // Ensure this user is registered in live_users so other users can see them
      final name = _myName;
      if (name.isNotEmpty) {
        _chatService.registerUser(name);
      }
    } catch (e) {
      debugPrint('[SecretConsoleScreen] Error loading settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to initialize secret console: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String get _myName {
    final savedName = _prefs?.getString('user_name')?.trim();
    if (savedName != null && savedName.isNotEmpty) {
      return savedName;
    }

    final overrideName = _prefs?.getString('local_override_creator_name')?.trim();
    if (overrideName != null && overrideName.isNotEmpty) {
      return overrideName;
    }

    return 'Unknown User';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Secret Console', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SecretConfigurationScreen()),
              ).then((_) {
                // Reload in case name changed
                _loadSettings();
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.neonPink))
          : _buildDirectMessagesTab(),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dateTime = timestamp.toDate().toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else {
      final day = dateTime.day.toString().padLeft(2, '0');
      final month = dateTime.month.toString().padLeft(2, '0');
      final year = dateTime.year.toString().substring(2);
      return '$day/$month/$year';
    }
  }

  Color _getAvatarColor(String seed) {
    final colors = [
      const Color(0xFF00A884), // WhatsApp Teal/Green
      const Color(0xFF1E88E5), // Blue
      const Color(0xFF8E24AA), // Purple
      const Color(0xFFD81B60), // Pink
      const Color(0xFFF4511E), // Deep Orange
      const Color(0xFF43A047), // Green
      const Color(0xFF00ACC1), // Teal
      const Color(0xFF3949AB), // Indigo
    ];
    int hash = 0;
    for (int i = 0; i < seed.length; i++) {
      hash = seed.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return colors[hash.abs() % colors.length];
  }

  void _showCreateChatFlow() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.deepSpaceBlackLight,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _NewMessageSheet(
        myUid: _myDeviceId ?? '',
        chatService: _chatService,
        getAvatarColor: _getAvatarColor,
        onUserSelected: (uid, name) {
          Navigator.pop(ctx);
          _promptSetChatCode(uid, name);
        },
      ),
    );
  }

  void _promptSetChatCode(String recipientUid, String recipientName) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.deepSpaceBlackLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Set Chat Code for $recipientName', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter a passcode that the receiver must enter to join and unlock the chat.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter chat code (e.g. 1234)',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonPink),
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.isEmpty) return;

              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                navigator.pop();
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => Center(
                    child: CircularProgressIndicator(color: AppColors.neonPink),
                  ),
                );

                await _chatService.createChatRoom(recipientUid, code);

                final roomId = await _chatService.getRoomId(recipientUid);
                await _prefs?.setBool('chat_verified_$roomId', true);

                if (!mounted) return;
                final myName = _myName;
                navigator.pop();
                navigator.push(
                  MaterialPageRoute(
                    builder: (context) => ChatRoomScreen(
                      recipientUid: recipientUid,
                      recipientName: recipientName,
                      senderName: myName.isNotEmpty ? myName : 'Me',
                    ),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text('Unable to create chat: $e'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Create', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _promptVerifyChatCode(String roomId, String correctCode, String recipientUid, String recipientName) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.deepSpaceBlackLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Enter Chat Code for $recipientName', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the chat code set by the sender to connect and open this chat.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter chat code',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonPink),
            onPressed: () async {
              final enteredCode = codeController.text.trim();
              if (enteredCode.isEmpty) return;

              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              if (enteredCode == correctCode) {
                navigator.pop();

                await _prefs?.setBool('chat_verified_$roomId', true);
                await _chatService.verifyChatRoom(roomId);

                if (!mounted) return;
                final myName = _myName;
                navigator.push(
                  MaterialPageRoute(
                    builder: (context) => ChatRoomScreen(
                      recipientUid: recipientUid,
                      recipientName: recipientName,
                      senderName: myName.isNotEmpty ? myName : 'Me',
                    ),
                  ),
                );
              } else {
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Incorrect chat code! Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Unlock', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleChatTap(Map<String, dynamic> user) async {
    final uid = user['uid'] as String? ?? '';
    final name = _chatService.resolveDisplayName(user, fallback: 'Unknown User');
    final displayName = uid == _myDeviceId ? '$name (You)' : name;
    final roomId = user['roomId'] as String? ?? '';
    final chatCodeCreator = user['chatCodeCreator'] as String?;
    final chatCode = user['chatCode'] as String?;

    final isLocallyVerified = _prefs?.getBool('chat_verified_$roomId') ?? false;

    // Check if we need to verify the code
    final needVerification = chatCode != null &&
        chatCodeCreator != _myDeviceId &&
        !isLocallyVerified;

    if (needVerification) {
      _promptVerifyChatCode(roomId, chatCode, uid, displayName);
    } else {
      // Go directly to chat screen
      final myName = _myName;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatRoomScreen(
            recipientUid: uid,
            recipientName: displayName,
            senderName: myName.isNotEmpty ? myName : 'Me',
          ),
        ),
      );
    }
  }

  Widget _buildDirectMessagesTab() {
    return Stack(
      children: [
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _chatService.getChatConversations(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'Chat loading error:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: AppColors.neonPink));
            }
            final users = snapshot.data ?? [];
            
            final requests = <Map<String, dynamic>>[];
            final chats = <Map<String, dynamic>>[];

            for (final user in users) {
              final roomId = user['roomId'] as String? ?? '';
              final chatCodeStatus = user['chatCodeStatus'] as String?;
              final chatCodeCreator = user['chatCodeCreator'] as String?;
              final isLocallyVerified = _prefs?.getBool('chat_verified_$roomId') ?? false;

              final isIncomingPending = chatCodeStatus == 'pending' &&
                  chatCodeCreator != _myDeviceId &&
                  !isLocallyVerified;

              if (isIncomingPending) {
                requests.add(user);
              } else {
                chats.add(user);
              }
            }

            final listItems = <Widget>[];

            // Incoming requests section
            if (requests.isNotEmpty) {
              listItems.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Icon(Icons.mark_email_unread_outlined, color: AppColors.neonPink, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Message Requests (${requests.length})',
                        style: TextStyle(
                          color: AppColors.neonPink,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              );

              for (final req in requests) {
                listItems.add(_buildChatTile(req, isRequest: true));
              }

              listItems.add(const Divider(color: Colors.white10, height: 24, thickness: 1));
            }

            // Normal Chats list
            listItems.add(
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  'Chats',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            );

            if (chats.isEmpty) {
              listItems.add(
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No chats yet. Tap the chat button below to start one!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                ),
              );
            } else {
              for (final chat in chats) {
                listItems.add(_buildChatTile(chat, isRequest: false));
              }
            }

            return Consumer(
              builder: (context, ref, child) {
                final currentSong = ref.watch(currentSongProvider).valueOrNull;
                final double bottomPadding = currentSong != null ? 148.0 : 80.0;
                return ListView(
                  padding: EdgeInsets.only(top: 8, bottom: bottomPadding),
                  children: listItems,
                );
              },
            );
          },
        ),
        Consumer(
          builder: (context, ref, child) {
            final currentSong = ref.watch(currentSongProvider).valueOrNull;
            final double bottomOffset = currentSong != null ? 148.0 : 80.0;
            return Positioned(
              bottom: bottomOffset,
              right: 24,
              child: FloatingActionButton(
                backgroundColor: AppColors.neonPink,
                child: const Icon(Icons.chat, color: Colors.white),
                onPressed: () {
                  _showCreateChatFlow();
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildChatTile(Map<String, dynamic> user, {required bool isRequest}) {
    final name = _chatService.resolveDisplayName(user, fallback: 'Unknown User');
    final uid = user['uid'] as String? ?? '';
    final isMe = uid == _myDeviceId;
    final displayName = isMe ? '$name (You)' : name;
    final roomId = user['roomId'] as String? ?? '';

    final lastMessage = user['lastMessage'] as String?;
    final lastTimestamp = user['lastTimestamp'] as Timestamp?;
    final lastSenderId = user['lastSenderId'] as String?;
    final chatCodeStatus = user['chatCodeStatus'] as String?;
    final chatCodeCreator = user['chatCodeCreator'] as String?;

    final isLocallyVerified = _prefs?.getBool('chat_verified_$roomId') ?? false;

    // A chat is locked if it has a code, we are not the creator, and we haven't verified it locally.
    final isLocked = chatCodeStatus != null &&
        chatCodeCreator != _myDeviceId &&
        !isLocallyVerified;

    // Parse status and heartbeat timestamp to check presence
    final status = user['status'] as String? ?? 'offline';
    final lastActive = user['lastActive'] as Timestamp?;
    bool isOnline = false;
    if (status == 'online' && lastActive != null) {
      final diff = DateTime.now().difference(lastActive.toDate()).inSeconds;
      if (diff <= 15) {
        isOnline = true;
      }
    }

    final unreadCount = user['unreadCount'] as int? ?? 0;
    final isLastMessageFromMe = lastMessage != null && lastSenderId == _myDeviceId;
    final hasUnread = unreadCount > 0 && !isRequest && !isLocked;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: _getAvatarColor(uid),
                child: Text(
                  name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'A',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
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
          title: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isOnline) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Online',
                          style: TextStyle(color: Color(0xFF25D366), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ] else if (lastActive != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Seen ${_formatTimestamp(lastActive)}',
                        style: const TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (lastTimestamp != null && !isRequest && !isLocked)
                Text(
                  _formatTimestamp(lastTimestamp),
                  style: TextStyle(
                    color: hasUnread ? const Color(0xFF25D366) : Colors.grey,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                if (isLocked) ...[
                  const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Locked • Tap to enter chat code',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ] else if (isRequest) ...[
                  const Icon(
                    Icons.mail_outline,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Tap to unlock message request',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ] else ...[
                  if (isLastMessageFromMe) ...[
                    const Icon(
                      Icons.done_all,
                      size: 16,
                      color: Color(0xFF53BDEB),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      lastMessage ?? 'Tap to start chatting...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasUnread ? Colors.white : Colors.grey,
                        fontSize: 14,
                        fontStyle: lastMessage == null ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                  if (hasUnread) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF25D366),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$unreadCount',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          onTap: () => _handleChatTap(user),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 80),
          child: Divider(color: Colors.white10, height: 1, thickness: 1),
        ),
      ],
    );
  }
}

// ── New Message Bottom Sheet ──────────────────────────────────────────────────
// Stateful so it can hold its own fetch state, search query, and loading flag.
// This prevents the FutureBuilder-inside-StatelessBuilder rebuild problem.

class _NewMessageSheet extends StatefulWidget {
  final String myUid;
  final LocalChatService chatService;
  final Color Function(String) getAvatarColor;
  final void Function(String uid, String name) onUserSelected;

  const _NewMessageSheet({
    required this.myUid,
    required this.chatService,
    required this.getAvatarColor,
    required this.onUserSelected,
  });

  @override
  State<_NewMessageSheet> createState() => _NewMessageSheetState();
}

class _NewMessageSheetState extends State<_NewMessageSheet> {
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  String? _error;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final users = await widget.chatService.getChatUsersOnce();
      final rooms = await widget.chatService.getAllChatRoomsOnce();

      final existingPartnerUids = rooms
          .map((r) => (r['users'] as List?)?.cast<String>() ?? [])
          .expand((u) => u)
          .where((u) => u != widget.myUid)
          .toSet();

      // Show ONLY new / not connected users
      final newUnconnectedUsers = users
          .where((u) {
            final uid = u['uid'] as String? ?? '';
            return uid.isNotEmpty && uid != widget.myUid && !existingPartnerUids.contains(uid);
          })
          .toList();

      if (mounted) {
        setState(() {
          _allUsers = newUnconnectedUsers;
          _filtered = newUnconnectedUsers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onSearch() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _allUsers
          : _allUsers.where((u) {
              final name = (u['name'] as String? ?? '').toLowerCase();
              return name.contains(q);
            }).toList();
    });
  }

  bool _isOnline(Map<String, dynamic> user) {
    final status = user['status'] as String? ?? '';
    final lastActive = user['lastActive'];
    if (status != 'online' || lastActive == null) return false;
    if (lastActive is Timestamp) {
      return DateTime.now().difference(lastActive.toDate()).inSeconds <= 30;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: screenH * 0.75 + keyboardH,
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ── Drag handle ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'New Message',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Refresh button
                IconButton(
                  onPressed: _isLoading ? null : _loadUsers,
                  icon: _isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.neonPink,
                          ),
                        )
                      : Icon(Icons.refresh_rounded,
                          color: AppColors.neonPink),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),

          // ── Search bar ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search users…',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.grey, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon:
                            const Icon(Icons.clear, color: Colors.grey, size: 18),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: AppColors.neonPink),
                  )
                : _error != null
                    ? _buildError()
                    : _filtered.isEmpty
                        ? _buildEmpty()
                        : _buildUserList(),
          ),
        ],
      ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.grey, size: 48),
              const SizedBox(height: 12),
              Text(
                'Could not load users.\n$_error',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadUsers,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonPink,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildEmpty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_outline, color: Colors.grey, size: 48),
              const SizedBox(height: 12),
              Text(
                _searchController.text.isNotEmpty
                    ? 'No users match "${_searchController.text}"'
                    : 'No other registered users yet.',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              if (_searchController.text.isEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Users appear here after they open the app\nand complete onboarding.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _buildUserList() => ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => const Divider(
          color: Colors.white10,
          height: 1,
          indent: 76,
        ),
        itemBuilder: (context, i) {
          final user = _filtered[i];
          final uid = user['uid'] as String? ?? '';
          final name = widget.chatService
              .resolveDisplayName(user, fallback: 'Unknown User');
          final online = _isOnline(user);
          final platform = user['platform'] as String? ?? '';

          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: widget.getAvatarColor(uid),
                  child: Text(
                    name.isNotEmpty
                        ? name.substring(0, 1).toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                // Online dot
                if (online)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: const Color(0xFF111111), width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (online) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Online',
                      style: TextStyle(
                        color: Color(0xFF25D366),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              platform.isNotEmpty ? platform : uid.substring(0, 8),
              style: const TextStyle(color: Colors.grey, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Container(
              decoration: BoxDecoration(
                color: AppColors.neonPink,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Text(
                  'Message',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            onTap: () => widget.onUserSelected(uid, name),
          );
        },
      );
}
