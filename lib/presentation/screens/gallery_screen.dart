import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../domain/entities/drive_photo.dart';
import '../../domain/entities/pairing.dart';
import '../../domain/entities/space.dart';
import '../providers/space_providers.dart';

/// Relationship-space dual-drive gallery screen.
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  final TextEditingController _partnerEmailController = TextEditingController();
  final TextEditingController _partnerUidController = TextEditingController();

  @override
  void dispose() {
    _partnerEmailController.dispose();
    _partnerUidController.dispose();
    super.dispose();
  }

  void _showPairDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Pair with Partner',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your partner\'s UID and Google Drive email to establish a secure, decoupled shared space.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _partnerUidController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Partner UID',
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF2A2A3E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _partnerEmailController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Partner Google Email',
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF2A2A3E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE91E63),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final uid = _partnerUidController.text.trim();
              final email = _partnerEmailController.text.trim();
              if (uid.isNotEmpty && email.isNotEmpty) {
                Navigator.of(ctx).pop();
                await ref.read(pairingStateProvider.notifier).pairWithUser(
                  partnerUid: uid,
                  partnerEmail: email,
                );
                ref.read(galleryPhotosProvider.notifier).loadPhotos(forceRefresh: true);
              }
            },
            child: const Text('Pair Now', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showUnpairDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Unpair Relationship Space?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Cross-user Drive access will be removed immediately. Your photos and memories will remain safely stored in your own Google Drive.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep Paired', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(pairingStateProvider.notifier).unpair();
              ref.read(galleryPhotosProvider.notifier).loadPhotos(forceRefresh: true);
            },
            child: const Text('Unpair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUpload() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      await ref.read(galleryPhotosProvider.notifier).uploadPhoto(
        filePath: file.path!,
        fileName: file.name,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairingState = ref.watch(pairingStateProvider);
    final photosAsync = ref.watch(galleryPhotosProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Aura Memories',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh Gallery',
            onPressed: () => ref.read(galleryPhotosProvider.notifier).loadPhotos(forceRefresh: true),
          ),
          if (pairingState.isPaired)
            IconButton(
              icon: const Icon(Icons.link_off, color: Colors.redAccent),
              tooltip: 'Unpair Space',
              onPressed: _showUnpairDialog,
            )
          else
            IconButton(
              icon: const Icon(Icons.favorite, color: Color(0xFFE91E63)),
              tooltip: 'Pair Space',
              onPressed: _showPairDialog,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFE91E63),
        onPressed: _handleUpload,
        icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
        label: const Text('Upload to My Drive', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          // ── Status Banner ──────────────────────────────────────────────────
          _buildSpaceStatusBanner(pairingState),

          // ── Photo Grid ────────────────────────────────────────────────────
          Expanded(
            child: photosAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFFE91E63)),
              ),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load gallery:\n$err',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => ref.read(galleryPhotosProvider.notifier).loadPhotos(forceRefresh: true),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (photos) {
                if (photos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          pairingState.isPaired ? Icons.photo_library_outlined : Icons.lock_outline,
                          color: Colors.white30,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          pairingState.isPaired
                              ? 'No memories yet in this shared space.\nUpload a photo to get started!'
                              : 'Solo mode: Photos are stored only in your Google Drive.\nPair with someone to unlock paired memories.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    return _buildPhotoCard(photo);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpaceStatusBanner(PairingState state) {
    Color bannerColor;
    IconData icon;
    String title;
    String subtitle;

    if (state.isPaired) {
      bannerColor = const Color(0xFF1E2E2A);
      icon = Icons.favorite;
      title = 'Paired Space Active';
      subtitle = 'Partner: ${state.activeSpace!.partnerEmail} • Dual Drive Feed';
    } else if (state.isTransitioning) {
      bannerColor = const Color(0xFF2E2A1E);
      icon = Icons.sync;
      title = 'Syncing Space...';
      subtitle = state.status == SpaceStatus.syncingPermissions
          ? 'Granting read-only permissions'
          : 'Initializing space folders';
    } else {
      bannerColor = const Color(0xFF1E1E2E);
      icon = Icons.cloud_done_outlined;
      title = 'Solo Drive Space';
      subtitle = 'All memories stored in your private Google Drive';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: state.isPaired ? const Color(0xFFE91E63) : Colors.cyanAccent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCard(DrivePhoto photo) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: photo.isMine ? const Color(0xFFE91E63).withValues(alpha: 0.3) : Colors.cyanAccent.withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo.thumbnailLink != null)
            Image.network(
              photo.thumbnailLink!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, color: Colors.white30, size: 40),
              ),
            )
          else
            const Center(
              child: Icon(Icons.image, color: Colors.white30, size: 40),
            ),

          // Owner Badge
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: photo.isMine ? const Color(0xFFE91E63) : Colors.cyan.shade800,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    photo.isMine ? Icons.person : Icons.favorite,
                    size: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    photo.isMine ? 'My Drive' : 'Partner Drive',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          // Delete button (for my photos only)
          if (photo.isMine)
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white70, size: 18),
                onPressed: () => ref.read(galleryPhotosProvider.notifier).deletePhoto(photo.id),
              ),
            ),
        ],
      ),
    );
  }
}
