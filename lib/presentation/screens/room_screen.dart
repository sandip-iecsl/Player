import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sync_provider.dart';
import '../providers/audio_provider.dart';

class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  final TextEditingController _joinController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _joinController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showPasswordDialog({required bool isHosting, Endpoint? endpoint}) {
    _passwordController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isHosting ? 'Set Room Password' : 'Enter Room Password',
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: _passwordController,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Password',
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954)),
            onPressed: () {
              final pass = _passwordController.text.trim();
              if (pass.isNotEmpty) {
                Navigator.pop(ctx);
                if (isHosting) {
                  ref.read(syncProvider.notifier).createRoom(pass);
                } else if (endpoint != null) {
                  ref.read(syncProvider.notifier).joinRoom(endpoint, pass);
                }
              }
            },
            child: Text(isHosting ? 'START' : 'JOIN',
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showNearbyRoomsSheet() {
    ref.read(syncProvider.notifier).startDiscovery();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Consumer(
          builder: (context, sheetRef, _) {
            final syncState = sheetRef.watch(syncProvider);
            return Container(
              padding: const EdgeInsets.all(24),
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nearby Aura Rooms',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Connecting via Nearby Connections...',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 16),
                  if (syncState.discoveredEndpoints.isEmpty)
                    const Expanded(
                        child: Center(
                            child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF1DB954)),
                        SizedBox(height: 16),
                        Text('Searching for friends...',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    )))
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: syncState.discoveredEndpoints.length,
                        itemBuilder: (context, index) {
                          final endpoint = syncState.discoveredEndpoints[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFF1DB954),
                              child: Icon(Icons.person, color: Colors.black),
                            ),
                            title: Text(endpoint.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            subtitle: const Text('Tap to join',
                                style: TextStyle(color: Colors.white54)),
                            onTap: () {
                              Navigator.pop(ctx);
                              _showPasswordDialog(
                                  isHosting: false, endpoint: endpoint);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Room',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
        actions: [
          if (syncState.isActive)
            IconButton(
              onPressed: () => ref.read(syncProvider.notifier).stopSync(),
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              tooltip: 'Leave Room',
            ),
        ],
      ),
      body: syncState.isActive ? _buildActiveRoom(syncState) : _buildIdleRoom(),
    );
  }

  Widget _buildIdleRoom() {
    final err = ref.watch(syncProvider).errorMessage;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.speaker_group_outlined,
              size: 80, color: Color(0xFF1DB954)),
          const SizedBox(height: 24),
          const Text(
            'Listen Together',
            style: TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sync your music with friends in real-time.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 48),
          if (err != null) ...[
            Text(err, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: () => _showPasswordDialog(isHosting: true),
              child: const Text('START A ROOM',
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white54, width: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: _showNearbyRoomsSheet,
              child: const Text('FIND NEARBY ROOMS',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveRoom(SyncState syncState) {
    final currentSong = ref.watch(currentSongProvider).valueOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),

          // Current playing song display (above room status)
          if (currentSong != null && syncState.isActive)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: const Color(0xFF1DB954).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  // Album art
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: currentSong.albumArt != null
                        ? Image.network(
                            currentSong.albumArt!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 48,
                              height: 48,
                              color: Colors.grey[800],
                              child: const Icon(Icons.music_note,
                                  color: Colors.white54, size: 24),
                            ),
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            color: Colors.grey[800],
                            child: const Icon(Icons.music_note,
                                color: Colors.white54, size: 24),
                          ),
                  ),
                  const SizedBox(width: 12),
                  // Song info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NOW PLAYING',
                          style: TextStyle(
                            color: Color(0xFF1DB954),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentSong.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          currentSong.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Sync status indicator
                  if (syncState.isSyncing)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1DB954).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.sync,
                        color: Color(0xFF1DB954),
                        size: 20,
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.speaker_group,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),

          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFF1DB954).withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  const Text('ROOM STATUS',
                      style: TextStyle(
                          color: Colors.grey, fontSize: 10, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  Text(
                    syncState.status == SyncStatus.hosting
                        ? 'HOSTING'
                        : 'JOINED',
                    style: const TextStyle(
                        color: Color(0xFF1DB954),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2),
                  ),
                  const SizedBox(height: 4),
                  if (syncState.isHost)
                    const Text('Visible as Aura Room',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  if (syncState.isSyncing) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(
                        color: Color(0xFF1DB954),
                        backgroundColor: Colors.white10),
                    const SizedBox(height: 4),
                    const Text('SYNCHRONIZING...',
                        style: TextStyle(
                            color: Color(0xFF1DB954),
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 40),
          const Text(
            'Participants',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                if (syncState.hostName != null)
                  _buildUserTile(syncState.hostName!, isHost: true),
                ...syncState.connectedEndpoints.entries.map((entry) {
                  final id = entry.key;
                  final name = entry.value;
                  final isReady = syncState.readyEndpoints[id] ?? false;
                  return _buildUserTile(name,
                      isHost: false,
                      isReady: isReady,
                      isSyncing: syncState.isSyncing);
                }),
              ],
            ),
          ),
          if (syncState.isSyncing)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              margin: const EdgeInsets.only(bottom: 16),
              width: double.infinity,
              decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF1DB954))),
                  SizedBox(width: 12),
                  Text('Every device sounding at once soon...',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildUserTile(String name,
      {required bool isHost, bool isReady = false, bool isSyncing = false}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor:
            isHost ? const Color(0xFF1DB954) : Colors.grey.shade800,
        child: Icon(Icons.person, color: isHost ? Colors.black : Colors.white),
      ),
      title: Row(
        children: [
          Text(name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          if (isHost) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF1DB954)),
              ),
              child: const Text('Host',
                  style: TextStyle(
                      color: Color(0xFF1DB954),
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ] else if (isSyncing) ...[
            const SizedBox(width: 8),
            Text(
              isReady ? 'READY' : 'BUFFERING...',
              style: TextStyle(
                  color: isReady ? const Color(0xFF1DB954) : Colors.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }
}
