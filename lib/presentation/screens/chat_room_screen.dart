import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/local_chat_service.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../data/models/chat_message_model.dart';
import '../providers/audio_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/events/event_dispatcher.dart';
import '../../core/events/chat_events.dart';
import '../../features/chat/engines/message_engine.dart';

class ChatRoomScreen extends StatefulWidget {
  final String recipientUid;
  final String recipientName;
  final String senderName;

  const ChatRoomScreen({
    super.key,
    required this.recipientUid,
    required this.recipientName,
    required this.senderName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _messageController = TextEditingController();
  final _chatService = LocalChatService();
  final _chatRepo = ChatRepository();
  
  String? _roomId;
  String? _myDeviceId;
  int _expiryHours = 24;
  bool _initializing = true;
  StreamSubscription? _messagesSubscription;
  String? _lastPlayedMessageId;
  
  List<ChatMessageModel> _messages = [];

  @override
  void initState() {
    super.initState();
    _initRoom();
  }

  Future<void> _initRoom() async {
    try {
      _myDeviceId = await _chatService.getDeviceId();
      _roomId = await _chatService.getRoomId(widget.recipientUid);
      _expiryHours = await LocalChatService.getChatExpiryHours();
      
      if (_roomId != null && _roomId!.isNotEmpty) {
        // Mark current active room in user presence
        await _chatService.updateCurrentRoom(_roomId);

        // Prune expired messages locally using the new MessageEngine
        await MessageEngine().pruneExpiredMessages(_roomId!);

        // Dispatch ConversationOpenedEvent to trigger Event Bus updates (Presence & Notification counts)
        EventDispatcher().publish(ConversationOpenedEvent(
          eventId: 'open_${DateTime.now().millisecondsSinceEpoch}_$_roomId',
          timestamp: DateTime.now(),
          roomId: _roomId!,
        ));

        // Load initial messages instantly from Cache (L1/L2)
        _messages = await _chatRepo.getMessages(_roomId!);
      }
    } catch (e) {
      debugPrint('[ChatRoomScreen] Initialization error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _initializing = false;
        });
      }
    }

    // Subscribe to Firestore for real-time delta synchronization
    if (_roomId != null && _roomId!.isNotEmpty) {
      _messagesSubscription = _chatService.getMessages(_roomId!).listen((snapshot) async {
        try {
          final List<ChatMessageModel> newMessages = [];
          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            newMessages.add(ChatMessageModel.fromJson(data, doc.id));
          }

          // Update ONLY the local caches (Hive L2 + L1 memory)
          // Do NOT call _chatRepo.sendMessage here — that would re-write to Firestore
          // and create an infinite loop.
          if (_chatRepo.msgCacheBox != null) {
            for (final msg in newMessages) {
              final cacheKey = '${_roomId!}_${msg.messageId}';
              await _chatRepo.msgCacheBox!.put(cacheKey, jsonEncode(msg.toJson()));
            }
          }
          // Rebuild sorted list from Firestore data
          newMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          _chatRepo.updateL1Cache(_roomId!, newMessages);
          
          if (mounted) {
            setState(() {
              _messages = List<ChatMessageModel>.from(newMessages);
            });
          }
        } catch (e) {
          debugPrint('[ChatRoomScreen] Message stream processing error: $e');
        }
      }, onError: (err) {
        debugPrint('[ChatRoomScreen] Message stream error: $err');
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messagesSubscription?.cancel();
    _chatService.updateCurrentRoom(null);
    if (_roomId != null) {
      EventDispatcher().publish(ConversationClosedEvent(
        eventId: 'close_${DateTime.now().millisecondsSinceEpoch}_$_roomId',
        timestamp: DateTime.now(),
        roomId: _roomId!,
      ));
    }
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    if (_myDeviceId == null || _roomId == null) return;

    final id = const Uuid().v4();
    final message = ChatMessageModel(
      messageId: id,
      senderId: _myDeviceId!,
      senderName: widget.senderName,
      text: text,
      timestamp: DateTime.now(),
    );

    // Optimistic UI update first
    setState(() {
      _messages.insert(0, message);
    });

    _messageController.clear();

    // Write to Firestore (also updates local caches)
    _chatRepo.sendMessage(_roomId!, message, recipientUid: widget.recipientUid);
  }

  void _promptUnlockChatCode(String correctCode) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.deepSpaceBlackLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Unlock Chat with ${widget.recipientName}', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the chat passcode set by the sender to unlock and join this chat.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter chat passcode',
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonPink),
            onPressed: () async {
              final enteredCode = codeController.text.trim();
              if (enteredCode.isEmpty) return;

              if (enteredCode == correctCode) {
                Navigator.pop(ctx);
                await _chatService.verifyChatRoom(_roomId!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Chat unlocked successfully! 🎉'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  setState(() {});
                }
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
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

  void _confirmClearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.deepSpaceBlackLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to clear all messages in this chat? This action cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _chatService.clearChat(_roomId!);
              if (mounted) {
                setState(() {
                  _messages.clear();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat cleared successfully!'), backgroundColor: Colors.green),
                );
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(ChatMessageModel message) {
    final isMe = message.senderId == _myDeviceId;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.deepSpaceBlackLight,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(message.isStarred ? Icons.star : Icons.star_border, color: Colors.amber),
              title: Text(message.isStarred ? 'Unstar Message' : 'Star Message', style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _chatRepo.toggleStarMessage(_roomId!, message);
                _initRoom(); // Refresh list
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.blueAccent),
              title: const Text('Copy Text', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: message.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to Clipboard'), backgroundColor: Colors.blueAccent),
                );
              },
            ),
            if (isMe && !message.deletedForEveryone)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete for Everyone', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _chatRepo.deleteForEveryone(_roomId!, message);
                  _initRoom(); // Refresh list
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: Text(widget.recipientName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(child: CircularProgressIndicator(color: AppColors.neonPink)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF2B1224),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.neonPink,
              child: Text(
                widget.recipientName.isNotEmpty ? widget.recipientName.substring(0, 1).toUpperCase() : 'U',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.recipientName,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: AppColors.deepSpaceBlackLight,
            onSelected: (val) {
              if (val == 'clear') _confirmClearChat();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear Chat', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFF1A0E17),
            ),
          ),
          StreamBuilder<DocumentSnapshot>(
            stream: _chatService.getRoomStream(_roomId!),
            builder: (context, roomSnapshot) {
              final roomData = roomSnapshot.data?.data() as Map<String, dynamic>?;
              final chatCodeStatus = roomData?['chatCodeStatus'] as String?;
              final chatCodeCreator = roomData?['chatCodeCreator'] as String?;
              final chatCode = roomData?['chatCode'] as String?;

              final isPending = chatCodeStatus == 'pending';
              final isCreator = chatCodeCreator == _myDeviceId;
              final isLocked = isPending && !isCreator;

              final cutoff = DateTime.now().subtract(Duration(hours: _expiryHours));
              final visibleMessages = _messages.where((m) => m.timestamp.isAfter(cutoff)).toList();

              return Column(
                children: [
                  if (isPending)
                    Container(
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.neonPink.withOpacity(0.15),
                            AppColors.neonCoral.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.neonPink.withOpacity(0.3)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            isCreator ? Icons.hourglass_empty : Icons.lock_outline,
                            color: AppColors.neonPink,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isCreator
                                  ? 'Message Request Sent. Share Chat Code: ${chatCode ?? ''}'
                                  : 'Message Request Pending. Enter Chat Code to accept and unlock.',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (!isCreator && chatCode != null) ...[
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.neonPink,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onPressed: () => _promptUnlockChatCode(chatCode),
                              child: const Text('Unlock', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  Expanded(
                    child: visibleMessages.isEmpty
                        ? const Center(
                            child: Text(
                              'No messages yet. Say Hello! 👋',
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          )
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            itemCount: visibleMessages.length,
                            itemBuilder: (context, index) {
                              final msg = visibleMessages[index];
                              final isMe = msg.senderId == _myDeviceId;
                              
                              return Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: GestureDetector(
                                  onLongPress: () => _showMessageOptions(msg),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isMe ? Colors.black : const Color(0xFF251622),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(isMe ? 16 : 4),
                                        topRight: Radius.circular(isMe ? 4 : 16),
                                        bottomLeft: const Radius.circular(16),
                                        bottomRight: const Radius.circular(16),
                                      ),
                                      border: isMe
                                          ? Border.all(color: const Color(0xFFFF2A7A))
                                          : null,
                                      boxShadow: isMe
                                          ? [
                                              BoxShadow(
                                                color: const Color(0xFFFF2A7A).withOpacity(0.4),
                                                blurRadius: 10,
                                                spreadRadius: 1,
                                              )
                                            ]
                                          : null,
                                    ),
                                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: isMe ? 0 : 5, sigmaY: isMe ? 0 : 5),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              msg.text,
                                              style: TextStyle(
                                                color: msg.deletedForEveryone
                                                    ? Colors.grey
                                                    : (isMe ? Colors.white : const Color(0xFF7D5C75)),
                                                fontSize: 14,
                                                height: 1.3,
                                                fontStyle: msg.deletedForEveryone ? FontStyle.italic : null,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                if (msg.isStarred)
                                                  const Padding(
                                                    padding: EdgeInsets.only(right: 4),
                                                    child: Icon(Icons.star, color: Colors.amber, size: 10),
                                                  ),
                                                Text(
                                                  msg.timestamp.toLocal().toString().substring(11, 16),
                                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Consumer(
                    builder: (context, ref, child) {
                      return ClipRRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            decoration: const BoxDecoration(
                              color: Colors.transparent,
                              border: Border(top: BorderSide(color: Colors.white10)),
                            ),
                            child: SafeArea(
                              top: false,
                              bottom: false,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        color: Colors.black.withOpacity(0.5),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.white.withOpacity(0.05),
                                            blurRadius: 1,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: TextField(
                                        controller: _messageController,
                                        enabled: !isLocked,
                                        style: const TextStyle(color: Colors.white),
                                        decoration: InputDecoration(
                                          hintText: isLocked
                                              ? 'Waiting for receiver (Code: $chatCode)...'
                                              : 'Type a message...',
                                          hintStyle: const TextStyle(color: Colors.white30),
                                          filled: true,
                                          fillColor: Colors.transparent,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: isLocked ? null : _sendMessage,
                                    child: CircleAvatar(
                                      radius: 20,
                                      backgroundColor: isLocked ? Colors.grey.shade800 : const Color(0xFFFF7E40),
                                      child: const Icon(Icons.send, color: Colors.white, size: 16),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
