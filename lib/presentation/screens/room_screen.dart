import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sync_provider.dart';
import '../providers/audio_provider.dart';
import '../../core/constants/app_colors.dart';

import '../providers/theme_provider.dart';

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
        backgroundColor: AppColors.deepSpaceBlackLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isHosting ? 'Set Room Password' : 'Enter Room Password',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: _passwordController,
          obscureText: true,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Password',
            hintStyle: TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.deepSpaceBlackLighter,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonPink),
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
                style: TextStyle(
                    color: AppColors.deepSpaceBlack, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showNearbyRoomsSheet() {
    ref.read(syncProvider.notifier).startDiscovery();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.deepSpaceBlackLight,
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
                  Text('Nearby Aura Rooms',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Connecting via Nearby Connections...',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 16),
                  if (syncState.discoveredEndpoints.isEmpty)
                    Expanded(
                        child: Center(
                            child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.neonPink),
                        SizedBox(height: 16),
                        Text('Searching for friends...',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    )))
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: syncState.discoveredEndpoints.length,
                        itemBuilder: (context, index) {
                          final endpoint = syncState.discoveredEndpoints[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.neonPink,
                              child: Icon(Icons.person, color: AppColors.deepSpaceBlack),
                            ),
                            title: Text(endpoint.name,
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text('Tap to join',
                                style: TextStyle(color: AppColors.textSecondary)),
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
    ref.watch(themeModeProvider);
    ref.watch(themeColorProvider);
    final syncState = ref.watch(syncProvider);

    return Scaffold(
      backgroundColor: AppColors.deepSpaceBlack,
      appBar: AppBar(
        backgroundColor: AppColors.deepSpaceBlack,
        elevation: 0,
        title: Text('Room',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
        actions: [
          if (syncState.isActive)
            IconButton(
              onPressed: () => ref.read(syncProvider.notifier).stopSync(),
              icon: Icon(Icons.logout_rounded, color: AppColors.neonCoral),
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
          Icon(Icons.speaker_group_outlined,
              size: 80, color: AppColors.neonPink),
          const SizedBox(height: 24),
          Text(
            'Listen Together',
            style: TextStyle(
                color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Sync your music with friends in real-time.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 48),
          if (err != null) ...[
            Text(err, style: TextStyle(color: AppColors.neonCoral)),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonPink,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: () => _showPasswordDialog(isHosting: true),
              child: Text('START A ROOM',
                  style: TextStyle(
                      color: AppColors.deepSpaceBlack,
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
                side: BorderSide(color: AppColors.divider, width: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: _showNearbyRoomsSheet,
              child: Text('FIND NEARBY ROOMS',
                  style: TextStyle(
                      color: AppColors.textPrimary,
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
                color: AppColors.neonPink.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: AppColors.neonPink.withOpacity(0.3)),
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
                              color: AppColors.deepSpaceBlackLighter,
                              child: Icon(Icons.music_note,
                                  color: AppColors.textSecondary, size: 24),
                            ),
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            color: AppColors.deepSpaceBlackLighter,
                            child: Icon(Icons.music_note,
                                color: AppColors.textSecondary, size: 24),
                          ),
                  ),
                  const SizedBox(width: 12),
                  // Song info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NOW PLAYING',
                          style: TextStyle(
                            color: AppColors.neonPink,
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
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          currentSong.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
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
                        color: AppColors.neonPink.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.sync,
                        color: AppColors.neonPink,
                        size: 20,
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.deepSpaceBlackLighter,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.speaker_group,
                        color: AppColors.textPrimary,
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
                color: AppColors.deepSpaceBlackLighter,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.neonPink.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  Text('ROOM STATUS',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 10, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  Text(
                    syncState.status == SyncStatus.hosting
                        ? 'HOSTING'
                        : 'JOINED',
                    style: TextStyle(
                        color: AppColors.neonPink,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2),
                  ),
                  const SizedBox(height: 4),
                  if (syncState.isHost)
                    Text('Visible as Aura Room',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  if (syncState.isSyncing) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                        color: AppColors.neonPink,
                        backgroundColor: AppColors.deepSpaceBlackLight),
                    const SizedBox(height: 4),
                    Text('SYNCHRONIZING...',
                        style: TextStyle(
                            color: AppColors.neonPink,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 40),
          Text(
            'Participants',
            style: TextStyle(
                color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
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
                  color: AppColors.deepSpaceBlackLight,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.neonPink)),
                  SizedBox(width: 12),
                  Text('Every device sounding at once soon...',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
            isHost ? AppColors.neonPink : AppColors.deepSpaceBlackLighter,
        child: Icon(Icons.person, color: isHost ? AppColors.deepSpaceBlack : AppColors.textPrimary),
      ),
      title: Row(
        children: [
          Text(name,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          if (isHost) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.neonPink.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.neonPink),
              ),
              child: Text('Host',
                  style: TextStyle(
                      color: AppColors.neonPink,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ] else if (isSyncing) ...[
            const SizedBox(width: 8),
            Text(
              isReady ? 'READY' : 'BUFFERING...',
              style: TextStyle(
                  color: isReady ? AppColors.neonPink : AppColors.neonCoral,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }
}