import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/song.dart';
import '../providers/download_provider.dart';

class AnimatedDownloadButton extends ConsumerStatefulWidget {
  final Song song;
  final VoidCallback? onDownloadComplete;

  const AnimatedDownloadButton({
    super.key,
    required this.song,
    this.onDownloadComplete,
  });

  @override
  ConsumerState<AnimatedDownloadButton> createState() =>
      _AnimatedDownloadButtonState();
}

class _AnimatedDownloadButtonState extends ConsumerState<AnimatedDownloadButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticInOut),
    );

    _rotateAnimation = Tween<double>(begin: 0, end: 2 * 3.14159).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDownloaded = ref.watch(isSongDownloadedProvider(widget.song));
    final progress = ref.watch(downloadProgressProvider);
    final songProgress = progress[widget.song.id] ?? 0.0;

    return isDownloaded.when(
      data: (downloaded) {
        if (downloaded) {
          return _buildDownloadedButton();
        }
        return _buildDownloadButton(songProgress);
      },
      loading: () => _buildLoadingButton(),
      error: (error, stack) => _buildErrorButton(),
    );
  }

  Widget _buildDownloadButton(double progress) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (progress > 0 && progress < 1) {
      return _buildProgressButton(progress, isDark);
    }

    return GestureDetector(
      onTap: () {
        _controller.forward(from: 0.0);
        ref.read(downloadSongProvider.notifier).downloadSong(widget.song);
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.neonPurple,
                AppColors.neonCyan,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.neonPurple.withOpacity(0.6),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(
            Icons.download_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildProgressButton(double progress, bool isDark) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.neonPurple.withOpacity(0.7),
            AppColors.neonCyan.withOpacity(0.7),
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDark ? Colors.white : AppColors.deepSpaceBlack,
              ),
              backgroundColor: Colors.grey.withOpacity(0.3),
            ),
          ),
          Text(
            '${(progress * 100).toInt()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadedButton() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.neonGreen,
            AppColors.neonCyan,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonGreen.withOpacity(0.6),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: GestureDetector(
        onLongPress: () {
          _showDeleteDialog();
        },
        child: const Icon(
          Icons.check_circle_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildLoadingButton() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.neonPurple.withOpacity(0.5),
            AppColors.neonCyan.withOpacity(0.5),
          ],
        ),
      ),
      child: RotationTransition(
        turns: _rotateAnimation,
        child: const Icon(
          Icons.downloading_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildErrorButton() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.neonPink.withOpacity(0.7),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonPink.withOpacity(0.6),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(
        Icons.error_rounded,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Download?'),
        content: Text('Remove "${widget.song.title}" from downloads?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(downloadSongProvider.notifier).deleteSong(widget.song);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}