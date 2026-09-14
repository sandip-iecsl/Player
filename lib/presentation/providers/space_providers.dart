import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/repositories/gallery_repository_impl.dart';
import '../../data/repositories/space_repository_impl.dart';
import '../../data/services/drive_service.dart';
import '../../data/services/drive_space_service.dart';
import '../../data/services/permission_sync_service.dart';
import '../../domain/entities/drive_photo.dart';
import '../../domain/entities/pairing.dart';
import '../../domain/entities/space.dart';
import '../../domain/repositories/gallery_repository.dart';
import '../../domain/repositories/space_repository.dart';
import '../../domain/services/pairing_orchestrator.dart';

// ── Foundational Service Providers ──────────────────────────────────────────

final driveServiceProvider = Provider<DriveService>((ref) {
  return DriveService();
});

final spaceRepositoryProvider = Provider<SpaceRepository>((ref) {
  return SpaceRepositoryImpl();
});

final galleryRepositoryProvider = Provider<GalleryRepository>((ref) {
  final spaceRepo = ref.watch(spaceRepositoryProvider);
  final driveService = ref.watch(driveServiceProvider);
  return GalleryRepositoryImpl(
    spaceRepository: spaceRepo,
    driveService: driveService,
  );
});

final driveSpaceServiceProvider = Provider<DriveSpaceService>((ref) {
  final spaceRepo = ref.watch(spaceRepositoryProvider);
  final driveService = ref.watch(driveServiceProvider);
  return DriveSpaceService(
    spaceRepository: spaceRepo,
    driveService: driveService,
  );
});

final permissionSyncServiceProvider = Provider<PermissionSyncService>((ref) {
  return PermissionSyncService();
});

// ── Pairing Orchestrator & State Provider ───────────────────────────────────

final pairingOrchestratorProvider = Provider<PairingOrchestrator>((ref) {
  final spaceRepo = ref.watch(spaceRepositoryProvider);
  final galleryRepo = ref.watch(galleryRepositoryProvider);
  final driveSpaceService = ref.watch(driveSpaceServiceProvider);
  final permissionSyncService = ref.watch(permissionSyncServiceProvider);

  final orchestrator = PairingOrchestrator(
    spaceRepository: spaceRepo,
    galleryRepository: galleryRepo,
    driveSpaceService: driveSpaceService,
    permissionSyncService: permissionSyncService,
  );

  final currentUid = FirebaseAuth.instance.currentUser?.uid;
  if (currentUid != null) {
    orchestrator.init(currentUid);
  }

  ref.onDispose(() => orchestrator.dispose());
  return orchestrator;
});

class PairingNotifier extends StateNotifier<PairingState> {
  final PairingOrchestrator _orchestrator;
  final DriveService _driveService;

  PairingNotifier(this._orchestrator, this._driveService) : super(_orchestrator.state) {
    _orchestrator.stateStream.listen((newState) {
      state = newState;
    });
  }

  Future<void> pairWithUser({
    required String partnerUid,
    required String partnerEmail,
  }) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      state = state.copyWith(
        status: SpaceStatus.error,
        errorMessage: 'User is not authenticated with Firebase.',
      );
      return;
    }

    final driveApi = _driveService.driveApi ?? await _driveService.signIn();
    final userEmail = _driveService.currentUser?.email ?? authUser.email ?? 'user@auraplayer.app';

    await _orchestrator.pairWithUser(
      currentUid: authUser.uid,
      currentUserEmail: userEmail,
      partnerUid: partnerUid,
      partnerEmail: partnerEmail,
      driveApi: driveApi,
    );
  }

  Future<void> unpair() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    final driveApi = _driveService.driveApi ?? await _driveService.signIn();
    final userEmail = _driveService.currentUser?.email ?? authUser.email ?? 'user@auraplayer.app';

    await _orchestrator.unpair(
      currentUid: authUser.uid,
      currentUserEmail: userEmail,
      driveApi: driveApi,
    );
  }
}

final pairingStateProvider = StateNotifierProvider<PairingNotifier, PairingState>((ref) {
  final orchestrator = ref.watch(pairingOrchestratorProvider);
  final driveService = ref.watch(driveServiceProvider);
  return PairingNotifier(orchestrator, driveService);
});

// ── Active Space Stream Provider ────────────────────────────────────────────

final activeSpaceProvider = StreamProvider<SpaceEntity?>((ref) {
  final spaceRepo = ref.watch(spaceRepositoryProvider);
  final authUser = FirebaseAuth.instance.currentUser;
  if (authUser == null) return Stream.value(null);
  return spaceRepo.watchActiveSpace(uid: authUser.uid);
});

// ── Gallery Photos Provider ─────────────────────────────────────────────────

class GalleryPhotosNotifier extends StateNotifier<AsyncValue<List<DrivePhoto>>> {
  final GalleryRepository _galleryRepo;
  final DriveService _driveService;

  GalleryPhotosNotifier(this._galleryRepo, this._driveService)
      : super(const AsyncValue.loading()) {
    loadPhotos();
  }

  Future<void> loadPhotos({bool forceRefresh = false}) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      state = const AsyncValue.data([]);
      return;
    }

    if (forceRefresh) {
      state = const AsyncValue.loading();
    }

    try {
      final driveApi = _driveService.driveApi ?? await _driveService.signInSilently();
      if (driveApi == null) {
        state = const AsyncValue.data([]);
        return;
      }

      final photos = await _galleryRepo.getActiveGalleryPhotos(
        currentUid: authUser.uid,
        driveApi: driveApi,
        forceRefresh: forceRefresh,
      );

      state = AsyncValue.data(photos);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> uploadPhoto({
    required String filePath,
    required String fileName,
  }) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    try {
      final driveApi = _driveService.driveApi ?? await _driveService.signIn();
      await _galleryRepo.uploadPhoto(
        currentUid: authUser.uid,
        filePath: filePath,
        fileName: fileName,
        driveApi: driveApi,
      );
      await loadPhotos(forceRefresh: true);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deletePhoto(String fileId) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    try {
      final driveApi = _driveService.driveApi ?? await _driveService.signIn();
      await _galleryRepo.deleteMyPhoto(
        currentUid: authUser.uid,
        fileId: fileId,
        driveApi: driveApi,
      );
      await loadPhotos(forceRefresh: true);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final galleryPhotosProvider =
    StateNotifierProvider<GalleryPhotosNotifier, AsyncValue<List<DrivePhoto>>>((ref) {
  final galleryRepo = ref.watch(galleryRepositoryProvider);
  final driveService = ref.watch(driveServiceProvider);
  return GalleryPhotosNotifier(galleryRepo, driveService);
});
