import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/playlist_provider.dart';
import 'playlist_screen.dart';
import '../widgets/playlist_dialogs.dart';
import 'local_songs_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Your Library',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
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
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.folder_shared, color: Color(0xFF1DB954)),
            ),
            title: const Text('Local Files',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text('Songs on your device',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const LocalSongsScreen())),
          ),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: playlists.isEmpty
                ? _buildEmptyState(context, ref)
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final isFav = playlist.id == favoritesId;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: isFav
                              ? Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF450AF5),
                                        Color(0xFFC4EFD9)
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(Icons.favorite,
                                      color: Colors.white, size: 32),
                                )
                              : playlist.coverUrl != null
                                  ? Image.network(playlist.coverUrl!,
                                      width: 64, height: 64, fit: BoxFit.cover)
                                  : Container(
                                      width: 64,
                                      height: 64,
                                      color: Colors.grey.shade900,
                                      child: const Icon(Icons.music_note,
                                          color: Colors.white54, size: 32),
                                    ),
                        ),
                        title: Text(
                          isFav ? 'Favourite' : playlist.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                            'Playlist • ${playlist.songs.length} songs',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 14)),
                        onTap: () {
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
                        onLongPress: () =>
                            _showDeleteDialog(context, ref, playlist),
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
              size: 80, color: Colors.grey.shade800),
          const SizedBox(height: 16),
          const Text('Create your first playlist',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('It\'s easy, we\'ll help you.',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => PlaylistDialogs.showCreatePlaylist(context, ref),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
        backgroundColor: const Color(0xFF282828),
        title: Text('Delete "${playlist.name}"?',
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              ref.read(playlistProvider.notifier).deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: const Text('DELETE',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
