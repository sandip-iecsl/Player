import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/audio_service.dart'; // PlaybackContext
import '../providers/local_music_provider.dart';
import '../providers/audio_provider.dart';

class LocalSongsScreen extends ConsumerWidget {
  const LocalSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localSongsAsync = ref.watch(allLocalSongsProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Local Files',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: localSongsAsync.when(
        data: (songs) => songs.isEmpty
            ? const Center(
                child: Text('No local songs found',
                    style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  final song = songs[index];
                  return ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child:
                          const Icon(Icons.music_note, color: Colors.white70),
                    ),
                    title: Text(song.title,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(song.artist,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                    onTap: () {
                      ref
                          .read(audioServiceProvider)
                          .loadQueue(songs, startIndex: index, context: PlaybackContext.local);
                    },
                  );
                },
              ),
        loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF1DB954))),
        error: (err, stack) => Center(
            child:
                Text('Error: $err', style: const TextStyle(color: Colors.red))),
      ),
    );
  }
}
