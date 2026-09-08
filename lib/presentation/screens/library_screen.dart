import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/playlist_provider.dart';
import '../providers/connectivity_provider.dart';
import 'playlist_screen.dart';
import '../widgets/playlist_dialogs.dart';
import '../../data/services/offline_storage_service.dart';
import 'local_songs_screen.dart';
import 'ml_training_screen.dart';
import '../../core/constants/app_colors.dart';
import '../providers/theme_provider.dart';
import '../../features/admin/engines/security_engine.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool? _isAdmin; // null = still checking

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    final result = await SecurityEngine().isCurrentUserAdmin();
    if (mounted) setState(() => _isAdmin = result);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeModeProvider);
    ref.watch(themeColorProvider);
    final playlists = ref.watch(playlistProvider);
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;

    return Scaffold(
      backgroundColor: AppColors.deepSpaceBlack,
      appBar: AppBar(
        backgroundColor: AppColors.deepSpaceBlack,
        elevation: 0,
        title: Text('Your Library',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: AppColors.textPrimary),
            onPressed: () => PlaylistDialogs.showCreatePlaylist(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                  color: AppColors.deepSpaceBlackLight,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.folder_shared, color: AppColors.neonPink),
            ),
            title: Text('Local Files',
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            subtitle: Text('Songs on your device',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const LocalSongsScreen())),
          ),

          // Admin Panel — only shown when isAdmin == true in Firestore
          if (_isAdmin == true)
            ListTile(
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                    color: AppColors.deepSpaceBlackLight,
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.admin_panel_settings_rounded,
                    color: AppColors.neonPink),
              ),
              title: Text('Admin Panel',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold)),
              subtitle: Text('Configure search synonyms & ML rules',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              onTap: () => _showAdminPasswordDialog(context),
            ),

          // OFFLINE PLAYLIST
          ValueListenableBuilder(
            valueListenable: Hive.box('offline_songs').listenable(),
            builder: (context, Box box, _) {
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/offline_banner.png',
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                          color: AppColors.deepSpaceBlackLight,
                          borderRadius: BorderRadius.circular(8)),
                      child:
                          Icon(Icons.offline_pin, color: AppColors.neonPink),
                    ),
                  ),
                ),
                title: Text('Offline',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold)),
                subtitle: Text('${box.length} downloaded songs',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                onTap: () {
                  final offlineSongs = OfflineStorageService.getOfflineSongs();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlaylistScreen(
                        playlistId: 'offline',
                        playlistTitle: 'Offline',
                        coverUrl: null,
                        songs: offlineSongs,
                      ),
                    ),
                  );
                },
              );
            },
          ),

          Expanded(
            child: playlists.isEmpty
                ? _buildEmptyState(context, ref)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final isFav = playlist.id == favoritesId;

                      return Opacity(
                        opacity: isOnline ? 1.0 : 0.4,
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: isFav
                                ? Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          AppColors.neonPink,
                                          AppColors.neonCoral
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(Icons.favorite,
                                        color: AppColors.textPrimary, size: 32),
                                  )
                                : playlist.coverUrl != null
                                    ? Image.network(playlist.coverUrl!,
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.cover)
                                    : Container(
                                        width: 64,
                                        height: 64,
                                        color: AppColors.deepSpaceBlackLighter,
                                        child: Icon(Icons.music_note,
                                            color: AppColors.textSecondary,
                                            size: 32),
                                      ),
                          ),
                          title: Text(
                            isFav ? 'Favourite' : playlist.name,
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                              'Playlist • ${playlist.songs.length} songs',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 14)),
                          onTap: () {
                            if (!isOnline) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Online playlists are disabled in offline mode'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PlaylistScreen(
                                  playlistId: playlist.id,
                                  playlistTitle: playlist.name,
                                  coverUrl: playlist.coverUrl,
                                  songs: playlist.songs,
                                ),
                              ),
                            );
                          },
                          onLongPress: () {
                            if (isOnline) {
                              _showDeleteDialog(context, ref, playlist);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_music_outlined,
              size: 80, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text('Create your first playlist',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("It's easy, we'll help you.",
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => PlaylistDialogs.showCreatePlaylist(context, ref),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonPink,
              foregroundColor: AppColors.deepSpaceBlack,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Create playlist',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(
      BuildContext context, WidgetRef ref, Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.deepSpaceBlackLight,
        title: Text('Delete "${playlist.name}"?',
            style: TextStyle(color: AppColors.textPrimary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              ref.read(playlistProvider.notifier).deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: Text('DELETE',
                style: TextStyle(
                    color: AppColors.neonCoral,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAdminPasswordDialog(BuildContext context) {
    final controller = TextEditingController();
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => WillPopScope(
          onWillPop: () async => !isVerifying,
          child: AlertDialog(
            backgroundColor: AppColors.deepSpaceBlackLight,
            title: Text(
              'Admin Authentication',
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter Admin Passcode:',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: true,
                  enabled: !isVerifying,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Passcode',
                    hintStyle: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.4)),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                          color: AppColors.textSecondary.withOpacity(0.5)),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.neonPink),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed:
                    isVerifying ? null : () => Navigator.pop(ctx),
                child: Text('Cancel',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: isVerifying
                    ? null
                    : () async {
                        final passcode = controller.text.trim();
                        if (passcode.isEmpty) return;

                        setDialogState(() => isVerifying = true);

                        // Dual check: password AND isAdmin from Firestore
                        final result = await SecurityEngine()
                            .validateAdminAccess(passcode);

                        if (!ctx.mounted) return;

                        if (result.granted) {
                          Navigator.pop(ctx);
                          if (context.mounted) {
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const MLTrainingScreen()),
                            );
                          }
                        } else {
                          setDialogState(() => isVerifying = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(result.denyReason ??
                                  'Access denied.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                child: isVerifying
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: AppColors.neonPink,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Verify',
                        style: TextStyle(
                            color: AppColors.neonPink,
                            fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

