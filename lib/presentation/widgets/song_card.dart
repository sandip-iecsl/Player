import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/song.dart';
import 'default_album_art.dart';
import 'equalizer_bars.dart';

class SongCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final bool isPlaying;

  const SongCard({
    super.key,
    required this.song,
    required this.onTap,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isPlaying
              ? AppColors.neonPurple.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album Art
            Stack(
              children: [
                AlbumArtImage(
                  imageUrl: song.albumArt,
                  width: 140,
                  height: 140,
                  borderRadius: BorderRadius.circular(12),
                ),
                if (isPlaying)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: EqualizerBars(
                          color: AppColors.neonPurple,
                          barCount: 4,
                          maxHeight: 30,
                          minHeight: 6,
                          barWidth: 4,
                          spacing: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Title
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
            const SizedBox(height: 4),
            // Artist
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
