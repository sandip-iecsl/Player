import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../../core/shared/error/drive_exceptions.dart';
import '../../core/shared/utils/space_utils.dart';
import '../../data/services/drive_space_service.dart';
import '../../data/services/permission_sync_service.dart';
import '../entities/pairing.dart';
import '../entities/space.dart';
import '../repositories/gallery_repository.dart';
import '../repositories/space_repository.dart';

/// Central domain orchestrator coordinating relationship pairing lifecycle,
/// deterministic space resolution, Google Drive folder creation/reuse,
/// permission synchronization, and unpairing workflows.
class PairingOrchestrator {
  final SpaceRepository _spaceRepository;
  final GalleryRepository _galleryRepository;
  final DriveSpaceService _driveSpaceService;
  final PermissionSyncService _permissionSyncService;

  PairingState _state = PairingState.initial();
  final _stateController = StreamController<PairingState>.broadcast();

  PairingState get state => _state;
  Stream<PairingState> get stateStream => _stateController.stream;

  PairingOrchestrator({
    required SpaceRepository spaceRepository,
    required GalleryRepository galleryRepository,
    DriveSpaceService? driveSpaceService,
    PermissionSyncService? permissionSyncService,
  })  : _spaceRepository = spaceRepository,
        _galleryRepository = galleryRepository,
        _driveSpaceService = driveSpaceService ?? DriveSpaceService(),
        _permissionSyncService = permissionSyncService ?? PermissionSyncService();

  void _updateState(PairingState newState) {
    _state = newState;
    _stateController.add(newState);
    debugPrint('[PAIRING] 🚦 State updated: ${_state.status.name} (loading: ${_state.isLoading})');
  }

  /// Initializes the orchestrator and checks for an existing active relationship space.
  Future<void> init(String currentUid) async {
    try {
      final activeSpace = await _spaceRepository.getActiveSpace(uid: currentUid);
      if (activeSpace != null) {
        _updateState(PairingState(
          status: SpaceStatus.active,
          activeSpace: activeSpace,
        ));
      } else {
        _updateState(PairingState.initial());
      }
    } catch (e) {
      debugPrint('[PAIRING] ⚠️ Failed to initialize active space: $e');
    }
  }

  /// Pairs the current user with a partner.
  /// Handles both first-time pairing and re-pairing with previous partners idempotently.
  Future<SpaceEntity> pairWithUser({
    required String currentUid,
    required String currentUserEmail,
    required String partnerUid,
    required String partnerEmail,
    required drive.DriveApi driveApi,
  }) async {
    final normUserEmail = SpaceUtils.normalizeEmail(currentUserEmail);
    final normPartnerEmail = SpaceUtils.normalizeEmail(partnerEmail);
    final spaceId = SpaceUtils.getSharedSpaceId(currentUid, partnerUid);

    debugPrint('[PAIRING] 🚀 Starting pairing flow: $normUserEmail <-> $normPartnerEmail (Space: $spaceId)');

    // 1. Transition to pending
    _updateState(_state.copyWith(
      status: SpaceStatus.pending,
      isLoading: true,
      clearErrorMessage: true,
    ));

    try {
      // 2. Transition to creatingSpace
      _updateState(_state.copyWith(status: SpaceStatus.creatingSpace));

      // Resolve/create user's relationship folder in their Google Drive
      final myFolderId = await _driveSpaceService.getOrCreateMySpaceFolder(
        currentUid: currentUid,
        currentUserEmail: normUserEmail,
        partnerUid: partnerUid,
        partnerEmail: normPartnerEmail,
        myDriveApi: driveApi,
      );

      // 3. Transition to syncingPermissions
      _updateState(_state.copyWith(status: SpaceStatus.syncingPermissions));

      // Grant partner reader access on the user's relationship folder
      await _permissionSyncService.grantPartnerReaderAccess(
        driveApi: driveApi,
        folderId: myFolderId,
        partnerEmail: normPartnerEmail,
      );

      // Check if partner already has a registered folder for this space
      String? partnerFolderId;
      final partnerSpace = await _spaceRepository.getSpace(uid: partnerUid, spaceId: spaceId);
      if (partnerSpace != null && partnerSpace.myDriveFolderId.isNotEmpty) {
        partnerFolderId = partnerSpace.myDriveFolderId;
        debugPrint('[PAIRING] 🤝 Found partner folder ID from space record: $partnerFolderId');
      }

      // 4. Save/Activate space record
      final now = DateTime.now();
      final spaceEntity = SpaceEntity(
        spaceId: spaceId,
        partnerUid: partnerUid,
        partnerEmail: normPartnerEmail,
        myDriveFolderId: myFolderId,
        partnerDriveFolderId: partnerFolderId,
        status: SpaceStatus.active,
        createdAt: now,
        lastPairedAt: now,
      );

      await _spaceRepository.saveSpace(uid: currentUid, space: spaceEntity);

      // 5. Invalidate gallery cache so both folders are freshly queried
      _galleryRepository.invalidateCache();

      // 6. Transition to active
      _updateState(_state.copyWith(
        status: SpaceStatus.active,
        activeSpace: spaceEntity,
        isLoading: false,
      ));

      debugPrint('[PAIRING] 🎉 Space $spaceId successfully activated!');
      return spaceEntity;
    } catch (e) {
      debugPrint('[PAIRING] ❌ Pairing failed: $e');
      _updateState(_state.copyWith(
        status: SpaceStatus.error,
        errorMessage: e.toString(),
        isLoading: false,
      ));
      if (e is DriveSpaceException) rethrow;
      throw DriveNetworkErrorException('Pairing operation encountered an error: $e', e);
    }
  }

  /// Unpairs the current active relationship.
  /// Revokes cross-user read permissions and archives the space.
  /// Historical photos and folders remain untouched in each user's Google Drive.
  Future<void> unpair({
    required String currentUid,
    required String currentUserEmail,
    required drive.DriveApi driveApi,
  }) async {
    final activeSpace = _state.activeSpace ?? await _spaceRepository.getActiveSpace(uid: currentUid);

    if (activeSpace == null) {
      debugPrint('[UNPAIR] ℹ️ No active relationship space to unpair.');
      _updateState(PairingState.initial());
      return;
    }

    debugPrint('[UNPAIR] 🚀 Unpairing from partner: ${activeSpace.partnerEmail} (Space: ${activeSpace.spaceId})');

    _updateState(_state.copyWith(
      status: SpaceStatus.unpairing,
      isLoading: true,
      clearErrorMessage: true,
    ));

    try {
      final now = DateTime.now();

      // 1. Mark space archived in Firestore
      await _spaceRepository.updateSpaceStatus(
        uid: currentUid,
        spaceId: activeSpace.spaceId,
        status: SpaceStatus.archived,
        archivedAt: now,
      );

      // 2. Revoke partner's reader permission on current user's folder
      if (activeSpace.myDriveFolderId.isNotEmpty) {
        await _permissionSyncService.revokePartnerReaderAccess(
          driveApi: driveApi,
          folderId: activeSpace.myDriveFolderId,
          partnerEmail: activeSpace.partnerEmail,
        );
      }

      // 3. Clear gallery cache so partner photos are removed from UI
      _galleryRepository.invalidateCache();

      // 4. Reset pairing state to archived/none
      _updateState(const PairingState(
        status: SpaceStatus.none,
        activeSpace: null,
        isLoading: false,
      ));

      debugPrint('[UNPAIR] ✅ Unpair completed successfully. Gallery reverted to own photos.');
    } catch (e) {
      debugPrint('[UNPAIR] ❌ Error during unpair: $e');
      _updateState(_state.copyWith(
        status: SpaceStatus.error,
        errorMessage: e.toString(),
        isLoading: false,
      ));
      rethrow;
    }
  }

  /// Reconciles partner folder ID when discovered via Firestore listener or pairing sync.
  Future<void> reconcilePartnerFolder({
    required String currentUid,
    required String spaceId,
    required String partnerFolderId,
  }) async {
    if (_state.activeSpace != null && _state.activeSpace!.spaceId == spaceId) {
      final updated = _state.activeSpace!.copyWith(partnerDriveFolderId: partnerFolderId);
      await _spaceRepository.updatePartnerFolderId(
        uid: currentUid,
        spaceId: spaceId,
        partnerFolderId: partnerFolderId,
      );
      _galleryRepository.invalidateCache();
      _updateState(_state.copyWith(activeSpace: updated));
      debugPrint('[PAIRING] 🔄 Reconciled partner folder ($partnerFolderId) into active space: $spaceId');
    }
  }

  void dispose() {
    _stateController.close();
  }
}
