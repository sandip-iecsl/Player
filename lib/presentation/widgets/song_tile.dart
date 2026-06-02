import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/song.dart';
import 'default_album_art.dart';
import 'playlist_dialogs.dart';

class SongTile extends ConsumerWidget {
  final Song song;
  final VoidCallback onTap;
  final bool isPlaying;

  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isPlaying
              ? AppColors.neonPurple.withValues(alpha: 0.12)
              : isDark
                  ? AppColors.deepSpaceBlackLight.withValues(alpha: 0.6)
                  : AppColors.cloudWhiteDark.withValues(alpha: 0.8),
          border: Border.all(
            color: isPlaying
                ? AppColors.neonPurple.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: isPlaying
              ? [
                  BoxShadow(
                    color: AppColors.neonPurple.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            // Album art with playing indicator overlay
            Stack(
              children: [
                AlbumArtImage(
                  imageUrl: song.albumArt,
                  width: 52,
                  height: 52,
                  borderRadius: BorderRadius.circular(10),
                ),
                if (isPlaying)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.equalizer_rounded,
                          color: AppColors.neonPurple, size: 22),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Title & artist
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isPlaying
                          ? AppColors.neonPurple
                          : isDark
                              ? AppColors.textPrimary
                              : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Duration
            Text(
              _fmt(song.duration),
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 4),
            // Action button (three dots)
            IconButton(
              icon: Icon(
                Icons.more_vert,
                color: isPlaying ? AppColors.neonPurple : AppColors.textSecondary,
                size: 20,
              ),
              onPressed: () => PlaylistDialogs.showSongOptions(context, ref, song),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
