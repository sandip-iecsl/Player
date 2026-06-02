import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';
import '../../main.dart'; // for navigatorKey
import '../providers/playlist_provider.dart';
import '../providers/audio_provider.dart';

class PlaylistDialogs {
  // ── Add to Playlist sheet ─────────────────────────────────────────────────

  static void showAddToPlaylist(BuildContext context, WidgetRef ref, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _AddToPlaylistSheet(song: song),
    );
  }

  // ── Create Playlist dialog ────────────────────────────────────────────────

  /// Shows the "Create New Playlist" dialog.
  /// Uses [navigatorKey] so this works from ANY context (full player, sheets, etc.)
  /// The dialog itself is a ConsumerStatefulWidget so it has its own live ref.
  static void showCreatePlaylist(
    BuildContext context,
    // ref is optional — dialog gets its own ref internally
    WidgetRef? ref, {
    Song? addSongAfter,
  }) {
    final ctx = navigatorKey.currentContext ?? context;
    showDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (_) => _CreatePlaylistDialog(addSongAfter: addSongAfter),
    );
  }

  // ── Song Options Sheet ────────────────────────────────────────────────────

  static void showSongOptions(BuildContext context, WidgetRef ref, Song song, {String? playlistId}) {
    final ctx = navigatorKey.currentContext ?? context;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play Next
              ListTile(
                leading: const Icon(Icons.skip_next, color: Colors.white),
                title: const Text('Play Next', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ref.read(audioServiceProvider).playNext(song);
                  
                  final navCtx = navigatorKey.currentContext;
                  if (navCtx != null && navCtx.mounted) {
                    ScaffoldMessenger.of(navCtx).showSnackBar(
                      SnackBar(
                        content: Text('${song.title} will play next'),
                        backgroundColor: const Color(0xFF1DB954),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              // Add to playlist
              ListTile(
                leading: const Icon(Icons.playlist_add, color: Colors.white),
                title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  // Brief delay to allow sheet to close
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (context.mounted) {
                      showAddToPlaylist(context, ref, song);
                    }
                  });
                },
              ),
              // Remove from playlist (if playlistId provided)
              if (playlistId != null)
                ListTile(
                  leading: const Icon(Icons.playlist_remove, color: Colors.redAccent),
                  title: const Text('Remove from Playlist', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    ref.read(playlistProvider.notifier).removeSongFromPlaylist(playlistId, song.id);
                    Navigator.pop(sheetContext);
                    
                    final navCtx = navigatorKey.currentContext;
                    if (navCtx != null && navCtx.mounted) {
                      ScaffoldMessenger.of(navCtx).showSnackBar(
                        SnackBar(
                          content: Text('Removed ${song.title} from playlist'),
                        ),
                      );
                    }
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ── Create Playlist Dialog ─────────────────────────────────────────────────────
// Uses its OWN ConsumerStatefulWidget ref so it's never stale after sheet pop.

class _CreatePlaylistDialog extends ConsumerStatefulWidget {
  final Song? addSongAfter;
  const _CreatePlaylistDialog({this.addSongAfter});

  @override
  ConsumerState<_CreatePlaylistDialog> createState() =>
      _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends ConsumerState<_CreatePlaylistDialog> {
  final _controller = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    if (_isCreating) return;

    setState(() => _isCreating = true);

    // Close dialog immediately for snappy feel
    if (mounted) Navigator.of(context).pop();

    // Create playlist using this widget's own live ref
    final playlistId =
        await ref.read(playlistProvider.notifier).createPlaylist(name);

    if (widget.addSongAfter != null) {
      await ref
          .read(playlistProvider.notifier)
          .addSongToPlaylist(playlistId, widget.addSongAfter!);
    }

    // Show confirmation via global navigator (always alive)
    final navCtx = navigatorKey.currentContext;
    if (navCtx != null && navCtx.mounted) {
      ScaffoldMessenger.of(navCtx).showSnackBar(
        SnackBar(
          content: Text(
            widget.addSongAfter != null
                ? 'Created "$name" · added ${widget.addSongAfter!.title}'
                : 'Playlist "$name" created',
          ),
          backgroundColor: const Color(0xFF1DB954),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF282828),
      title: const Text('Create New Playlist',
          style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        style: const TextStyle(color: Colors.white),
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          hintText: 'Playlist name',
          hintStyle: TextStyle(color: Colors.grey),
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        onSubmitted: (_) => _create(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: _isCreating ? null : _create,
          child: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF1DB954)),
                )
              : const Text('Create',
                  style: TextStyle(
                      color: Color(0xFF1DB954), fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ── Add To Playlist Sheet ─────────────────────────────────────────────────────

class _AddToPlaylistSheet extends ConsumerWidget {
  final Song song;
  const _AddToPlaylistSheet({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistProvider);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Add to Playlist',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // ── Create New Playlist ────────────────────────────────────────────
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.add, color: Color(0xFF1DB954)),
            ),
            title: const Text('Create New Playlist',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              // Pop sheet first
              Navigator.pop(context);
              // Small delay so the sheet fully dismisses before dialog opens
              Future.delayed(const Duration(milliseconds: 200), () {
                final ctx = navigatorKey.currentContext;
                if (ctx == null) return;
                showDialog(
                  context: ctx,
                  builder: (_) =>
                      _CreatePlaylistDialog(addSongAfter: song),
                );
              });
            },
          ),

          const Divider(color: Colors.white12),

          // ── Existing playlists ─────────────────────────────────────────────
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'No playlists yet. Create one above!',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: playlist.coverUrl != null
                          ? Image.network(playlist.coverUrl!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _thumb())
                          : _thumb(),
                    ),
                    title: Text(playlist.name,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${playlist.songs.length} songs',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                    onTap: () async {
                      await ref
                          .read(playlistProvider.notifier)
                          .addSongToPlaylist(playlist.id, song);
                      if (context.mounted) Navigator.pop(context);
                      final navCtx = navigatorKey.currentContext;
                      if (navCtx != null && navCtx.mounted) {
                        ScaffoldMessenger.of(navCtx).showSnackBar(
                          SnackBar(
                            content: Text('Added to ${playlist.name}'),
                            backgroundColor: const Color(0xFF1DB954),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _thumb() => Container(
        color: Colors.grey.shade800,
        width: 40,
        height: 40,
        child: const Icon(Icons.music_note, color: Colors.white54, size: 20),
      );
}
