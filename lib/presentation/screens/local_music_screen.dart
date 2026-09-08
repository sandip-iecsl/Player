import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/audio_service.dart'; // PlaybackContext
import '../providers/audio_provider.dart';
import '../providers/local_music_provider.dart';
import '../providers/history_provider.dart';
import '../../domain/entities/song.dart';
import '../widgets/playlist_dialogs.dart';
import '../../core/constants/app_colors.dart';

import '../providers/theme_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'secret_configuration_screen.dart';
import '../../features/admin/engines/security_engine.dart';
class LocalMusicScreen extends ConsumerWidget {
  const LocalMusicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider);
    ref.watch(themeColorProvider);
    final hasPermission = ref.watch(localPermissionProvider);

    return Scaffold(
      backgroundColor: AppColors.deepSpaceBlack,
      appBar: AppBar(
        backgroundColor: AppColors.deepSpaceBlack,
        leading: GestureDetector(
          onTap: () {}, // Camouflage
          onLongPress: () => _showSecretPasswordDialog(context),
          child: Container(
            alignment: Alignment.topLeft,
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.circle, size: 12, color: Colors.white.withOpacity(0.02)),
          ),
        ),
        title: Text('Local Music',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        actions: [
          if (hasPermission)
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
              onPressed: () {
                ref.invalidate(allLocalSongsProvider);
                ref.invalidate(localFoldersProvider);
              },
            ),
        ],
      ),
      body: !hasPermission
          ? _PermissionPrompt(onGrant: () =>
              ref.read(localPermissionProvider.notifier).requestOnce())
          : const _FolderView(),
    );
  }
}

// ── Permission prompt ───────────────────────────────────────────────────────
class _PermissionPrompt extends StatelessWidget {
  final VoidCallback onGrant;
  const _PermissionPrompt({required this.onGrant});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: AppColors.deepSpaceBlackLight,
                borderRadius: BorderRadius.circular(20)),
            child: Icon(Icons.folder_rounded,
                color: AppColors.neonPink, size: 64),
          ),
          const SizedBox(height: 24),
          Text('Access Your Music',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
            'Allow Aura Player to read your device storage and play local music.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onGrant,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonPink,
                foregroundColor: AppColors.deepSpaceBlack,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('Grant Permission',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Folder grid ─────────────────────────────────────────────────────────────
class _FolderView extends ConsumerWidget {
  const _FolderView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(localFoldersProvider);
    return foldersAsync.when(
      loading: () => Center(
          child: CircularProgressIndicator(color: AppColors.neonPink)),
      error: (e, _) => Center(
          child: Text('Error: $e', style: TextStyle(color: AppColors.neonCoral))),
      data: (folders) => folders.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.music_off_rounded, color: AppColors.textSecondary, size: 64),
                SizedBox(height: 16),
                Text('No music found on device',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                SizedBox(height: 8),
                Text('Add MP3/FLAC files to your Music folder',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ]),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.9,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: folders.length,
              itemBuilder: (_, i) => _FolderCard(folder: folders[i]),
            ),
    );
  }
}

// ── Folder card ─────────────────────────────────────────────────────────────
class _FolderCard extends ConsumerWidget {
  final LocalFolder folder;
  const _FolderCard({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => _FolderSongsScreen(folder: folder))),
      child: Container(
        decoration: BoxDecoration(
            color: AppColors.deepSpaceBlackLight,
            borderRadius: BorderRadius.circular(12)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Folder art placeholder
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              width: double.infinity,
              height: 130,
              color: AppColors.deepSpaceBlackLighter,
              child: Icon(Icons.folder_rounded,
                  color: AppColors.neonPink, size: 56),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
            child: Text(folder.name,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Text(
                '${folder.songs.length} song${folder.songs.length == 1 ? '' : 's'}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ),
        ]),
      ),
    );
  }
}

// ── Folder songs screen ─────────────────────────────────────────────────────
class _FolderSongsScreen extends ConsumerWidget {
  final LocalFolder folder;
  const _FolderSongsScreen({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = folder.songs;
    final currentSong = ref.watch(currentSongProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.deepSpaceBlack,
      appBar: AppBar(
        backgroundColor: AppColors.deepSpaceBlack,
        title: Text(folder.name,
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('${songs.length} songs',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
          ),
        ],
      ),
      body: Column(children: [
        // Play All / Shuffle
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: songs.isEmpty ? null : () {
                   ref.read(audioServiceProvider).loadQueue(
                    songs,
                    startIndex: 0,
                    context: PlaybackContext.local,
                  );
                  ref.read(recentlyPlayedProvider.notifier).add(songs.first);
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonPink,
                  foregroundColor: AppColors.deepSpaceBlack,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: songs.isEmpty ? null : () {
                  ref.read(audioServiceProvider).loadQueue(
                      List<Song>.from(songs)..shuffle(),
                      startIndex: 0,
                      context: PlaybackContext.local,
                  );
                },
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Shuffle'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.neonPink,
                  side: BorderSide(color: AppColors.neonPink),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),
          ]),
        ),
        // Songs list
        Expanded(
          child: ListView.builder(
            itemCount: songs.length,
            itemBuilder: (_, i) {
              final song = songs[i];
              final playing = currentSong?.id == song.id;
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: playing
                          ? AppColors.neonPink.withOpacity(0.2)
                          : AppColors.deepSpaceBlackLighter,
                      borderRadius: BorderRadius.circular(6)),
                  child: Icon(
                      playing
                          ? Icons.equalizer_rounded
                          : Icons.music_note_rounded,
                      color: AppColors.neonPink,
                      size: 22),
                ),
                title: Text(song.title,
                    style: TextStyle(
                        color: playing
                            ? AppColors.neonPink
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(song.artist,
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                // ── Professional 3-dot menu: Add to Playlist + Play Next
                trailing: IconButton(
                  icon: Icon(Icons.more_vert, color: AppColors.textSecondary),
                  onPressed: () => PlaylistDialogs.showSongOptions(context, ref, song),
                ),
                onTap: () {
                  ref
                      .read(audioServiceProvider)
                      .loadQueue(songs, startIndex: i, context: PlaybackContext.local);
                  ref.read(recentlyPlayedProvider.notifier).add(song);
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

void _showSecretPasswordDialog(BuildContext context) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.deepSpaceBlackLight,
      title: const Text('Developer Console',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter Developer Passcode:',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Passcode',
              hintStyle:
                  TextStyle(color: AppColors.textSecondary.withOpacity(0.4)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.neonPink)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () async {
            final passwordEntered = controller.text.trim();
            // Validate directly against Firestore — no hardcoded fallback
            final isValid = await SecurityEngine()
                .validateSecretConsolePasscode(passwordEntered);

            if (isValid) {
              if (ctx.mounted) {
                Navigator.pop(ctx);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('last_console_access_timestamp',
                    DateTime.now().millisecondsSinceEpoch);

                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                        builder: (context) =>
                            const SecretConfigurationScreen()),
                  );
                }
              }
            } else {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Access Denied',
                        style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.red));
              }
            }
          },
          child: Text('Unlock',
              style: TextStyle(color: AppColors.neonPink)),
        ),
      ],
    ),
  );
}