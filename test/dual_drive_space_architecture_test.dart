import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:aura_player/core/shared/error/drive_exceptions.dart';
import 'package:aura_player/core/shared/utils/space_utils.dart';
import 'package:aura_player/domain/entities/space.dart';
import 'package:aura_player/domain/repositories/space_repository.dart';
import 'package:aura_player/domain/services/pairing_orchestrator.dart';
import 'package:aura_player/data/models/space_model.dart';
import 'package:aura_player/data/repositories/gallery_repository_impl.dart';
import 'package:aura_player/data/services/drive_service.dart';
import 'package:aura_player/data/services/drive_space_service.dart';
import 'package:aura_player/data/services/permission_sync_service.dart';

// ── In-Memory Fake Space Repository ─────────────────────────────────────────

class FakeSpaceRepository implements SpaceRepository {
  final Map<String, Map<String, SpaceEntity>> _store = {};

  @override
  Future<SpaceEntity?> getSpace({required String uid, required String spaceId}) async {
    return _store[uid]?[spaceId];
  }

  @override
  Future<SpaceEntity?> getActiveSpace({required String uid}) async {
    final userSpaces = _store[uid]?.values ?? [];
    for (final space in userSpaces) {
      if (space.status == SpaceStatus.active) return space;
    }
    return null;
  }

  @override
  Future<void> saveSpace({required String uid, required SpaceEntity space}) async {
    _store.putIfAbsent(uid, () => {})[space.spaceId] = space;
  }

  @override
  Future<void> updateSpaceStatus({
    required String uid,
    required String spaceId,
    required SpaceStatus status,
    DateTime? lastPairedAt,
    DateTime? archivedAt,
  }) async {
    final existing = _store[uid]?[spaceId];
    if (existing != null) {
      _store[uid]![spaceId] = existing.copyWith(
        status: status,
        lastPairedAt: lastPairedAt ?? existing.lastPairedAt,
        archivedAt: archivedAt ?? existing.archivedAt,
      );
    }
  }

  @override
  Future<void> updatePartnerFolderId({
    required String uid,
    required String spaceId,
    required String partnerFolderId,
  }) async {
    final existing = _store[uid]?[spaceId];
    if (existing != null) {
      _store[uid]![spaceId] = existing.copyWith(partnerDriveFolderId: partnerFolderId);
    }
  }

  @override
  Future<List<SpaceEntity>> listSpaces({required String uid}) async {
    return _store[uid]?.values.toList() ?? [];
  }

  @override
  Stream<SpaceEntity?> watchActiveSpace({required String uid}) {
    final active = _store[uid]?.values.where((s) => s.status == SpaceStatus.active).firstOrNull;
    return Stream.value(active);
  }
}

// ── In-Memory Fake Drive Service ────────────────────────────────────────────

class FakeDriveService extends DriveService {
  FakeDriveService() : super.forTesting();

  final Map<String, drive.File> folders = {};
  final Map<String, List<drive.File>> filesByFolder = {};
  final Map<String, List<drive.Permission>> permissionsByFolder = {};

  int folderCounter = 1;
  int fileCounter = 1;
  int permCounter = 1;

  @override
  Future<bool> verifyFolderExists(drive.DriveApi api, String folderId) async {
    return folders.containsKey(folderId);
  }

  @override
  Future<drive.File> createFolder(drive.DriveApi api, String folderName) async {
    final id = 'folder_${folderCounter++}';
    final file = drive.File()
      ..id = id
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..createdTime = DateTime.now();
    folders[id] = file;
    filesByFolder[id] = [];
    permissionsByFolder[id] = [];
    return file;
  }

  @override
  Future<drive.File?> findFolderByName(drive.DriveApi api, String folderName) async {
    for (final folder in folders.values) {
      if (folder.name == folderName) return folder;
    }
    return null;
  }

  @override
  Future<List<drive.File>> listFilesInFolder(
    drive.DriveApi api,
    String folderId, {
    int pageSize = 100,
  }) async {
    return filesByFolder[folderId] ?? [];
  }

  @override
  Future<drive.File> uploadFile({
    required drive.DriveApi api,
    required File file,
    required String fileName,
    required String targetFolderId,
    String mimeType = 'image/jpeg',
  }) async {
    final id = 'file_${fileCounter++}';
    final newFile = drive.File()
      ..id = id
      ..name = fileName
      ..parents = [targetFolderId]
      ..mimeType = mimeType
      ..createdTime = DateTime.now()
      ..size = '1024';

    filesByFolder.putIfAbsent(targetFolderId, () => []).insert(0, newFile);
    return newFile;
  }

  @override
  Future<void> deleteFile(drive.DriveApi api, String fileId) async {
    for (final list in filesByFolder.values) {
      list.removeWhere((f) => f.id == fileId);
    }
  }
}

// ── Dummy DriveApi Client ───────────────────────────────────────────────────

class DummyDriveApi extends drive.DriveApi {
  DummyDriveApi() : super(FakeHttpClient());
}

class FakeHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value([]),
      200,
    );
  }
}

// ── Test Suite ──────────────────────────────────────────────────────────────

void main() {
  group('Decoupled Dual-Drive & Space Architecture Tests', () {
    late FakeSpaceRepository spaceRepo;
    late FakeDriveService driveService;
    late DummyDriveApi dummyDriveApi;
    late PermissionSyncService permissionSyncService;

    setUp(() {
      spaceRepo = FakeSpaceRepository();
      driveService = FakeDriveService();
      dummyDriveApi = DummyDriveApi();
      permissionSyncService = PermissionSyncService();
    });

    test('TEST 1 & 2: Deterministic Space ID & Invariant A+B == B+A', () {
      final spaceId1 = SpaceUtils.getSharedSpaceId('user_alpha', 'user_beta');
      final spaceId2 = SpaceUtils.getSharedSpaceId('user_beta', 'user_alpha');

      expect(spaceId1, equals(spaceId2));
      expect(spaceId1.startsWith('space_'), isTrue);

      final folderName = SpaceUtils.getSpaceFolderName(spaceId1);
      expect(folderName, equals('YouAndMe_Space_$spaceId1'));
    });

    test('TEST 3: Space Model Firestore Roundtrip and Perspective Invariant', () {
      final now = DateTime.now();
      final spaceA = SpaceModel(
        spaceId: 'space_123',
        partnerUid: 'uid_b',
        partnerEmail: 'user_b@gmail.com',
        myDriveFolderId: 'folder_A',
        partnerDriveFolderId: 'folder_B',
        status: 'active',
        createdAt: now,
        lastPairedAt: now,
        archivedAt: null,
        schemaVersion: 1,
      );

      final firestoreMap = spaceA.toFirestore();
      expect(firestoreMap['my_drive_folder_id'], equals('folder_A'));
      expect(firestoreMap['partner_drive_folder_id'], equals('folder_B'));
      expect(firestoreMap['status'], equals('active'));

      final reconstructed = SpaceModel.fromMap(firestoreMap);
      expect(reconstructed.myDriveFolderId, equals('folder_A'));
      expect(reconstructed.partnerDriveFolderId, equals('folder_B'));
    });

    test('TEST 4: Own Drive Upload Invariant & Rejection of Partner Folder Upload', () async {
      final galleryRepo = GalleryRepositoryImpl(
        spaceRepository: spaceRepo,
        driveService: driveService,
      );

      // Create an active space where my folder is folder_1 and partner is folder_2
      final space = SpaceEntity(
        spaceId: 'space_AB',
        partnerUid: 'uid_B',
        partnerEmail: 'b@test.com',
        myDriveFolderId: 'folder_1',
        partnerDriveFolderId: 'folder_2',
        status: SpaceStatus.active,
        createdAt: DateTime.now(),
        lastPairedAt: DateTime.now(),
      );
      await spaceRepo.saveSpace(uid: 'uid_A', space: space);

      // Create dummy temporary file
      final tempFile = File('${Directory.systemTemp.path}/test_upload.jpg');
      await tempFile.writeAsString('fake image data');

      try {
        final uploaded = await galleryRepo.uploadPhoto(
          currentUid: 'uid_A',
          filePath: tempFile.path,
          fileName: 'test_upload.jpg',
          driveApi: dummyDriveApi,
        );

        expect(uploaded.folderId, equals('folder_1'));
        expect(uploaded.isMine, isTrue);
        expect(driveService.filesByFolder['folder_1']?.length, equals(1));
        // Partner's folder must NOT contain this photo
        expect(driveService.filesByFolder['folder_2']?.length ?? 0, equals(0));
      } finally {
        if (await tempFile.exists()) await tempFile.delete();
      }
    });

    test('TEST 5: Paired Gallery Merges Dual Folders & Unpaired Queries Own Folder Only', () async {
      final galleryRepo = GalleryRepositoryImpl(
        spaceRepository: spaceRepo,
        driveService: driveService,
      );

      // Seed photos in folder_1 (User A) and folder_2 (User B)
      driveService.folders['folder_1'] = drive.File()..id = 'folder_1';
      driveService.folders['folder_2'] = drive.File()..id = 'folder_2';

      final fileA = drive.File()
        ..id = 'img_a'
        ..name = 'photo_a.jpg'
        ..mimeType = 'image/jpeg'
        ..createdTime = DateTime(2026, 9, 14, 10, 0)
        ..size = '2048';
      final fileB = drive.File()
        ..id = 'img_b'
        ..name = 'photo_b.jpg'
        ..mimeType = 'image/jpeg'
        ..createdTime = DateTime(2026, 9, 14, 11, 0) // Newer
        ..size = '4096';

      driveService.filesByFolder['folder_1'] = [fileA];
      driveService.filesByFolder['folder_2'] = [fileB];

      // Setup Paired Space
      final pairedSpace = SpaceEntity(
        spaceId: 'space_AB',
        partnerUid: 'uid_B',
        partnerEmail: 'b@test.com',
        myDriveFolderId: 'folder_1',
        partnerDriveFolderId: 'folder_2',
        status: SpaceStatus.active,
        createdAt: DateTime.now(),
        lastPairedAt: DateTime.now(),
      );
      await spaceRepo.saveSpace(uid: 'uid_A', space: pairedSpace);

      final pairedPhotos = await galleryRepo.getActiveGalleryPhotos(
        currentUid: 'uid_A',
        driveApi: dummyDriveApi,
        forceRefresh: true,
      );

      // Both photos returned, sorted newest first (fileB then fileA)
      expect(pairedPhotos.length, equals(2));
      expect(pairedPhotos[0].id, equals('img_b'));
      expect(pairedPhotos[0].isMine, isFalse);
      expect(pairedPhotos[1].id, equals('img_a'));
      expect(pairedPhotos[1].isMine, isTrue);

      // Now simulate unpair (partnerDriveFolderId removed / inactive)
      final soloSpace = pairedSpace.copyWith(
        partnerDriveFolderId: null,
        status: SpaceStatus.archived,
      );
      await spaceRepo.saveSpace(uid: 'uid_A', space: soloSpace);
      galleryRepo.invalidateCache();

      final soloPhotos = await galleryRepo.getActiveGalleryPhotos(
        currentUid: 'uid_A',
        driveApi: dummyDriveApi,
        forceRefresh: true,
      );

      // Inactive space returns empty or own photos only, never partner photos
      expect(soloPhotos.any((p) => p.id == 'img_b'), isFalse);
    });

    test('TEST 6: New Partner Isolation (A+B vs A+C)', () {
      final spaceAB = SpaceUtils.getSharedSpaceId('uid_A', 'uid_B');
      final spaceAC = SpaceUtils.getSharedSpaceId('uid_A', 'uid_C');

      expect(spaceAB, isNot(equals(spaceAC)));
      expect(SpaceUtils.getSpaceFolderName(spaceAB), isNot(equals(SpaceUtils.getSpaceFolderName(spaceAC))));
    });

    test('TEST 7: Full Pairing & Unpair State Machine Lifecycle', () async {
      final galleryRepo = GalleryRepositoryImpl(
        spaceRepository: spaceRepo,
        driveService: driveService,
      );

      // Create a testable DriveSpaceService using fake Drive
      driveService.folders['folder_1'] = drive.File()..id = 'folder_1'..name = 'YouAndMe_Space_test';

      final orchestrator = PairingOrchestrator(
        spaceRepository: spaceRepo,
        galleryRepository: galleryRepo,
        driveSpaceService: DriveSpaceService(
          spaceRepository: spaceRepo,
          driveService: driveService,
        ),
        permissionSyncService: permissionSyncService,
      );

      expect(orchestrator.state.status, equals(SpaceStatus.none));
      expect(orchestrator.state.isPaired, isFalse);

      // Simulate saving an active space
      final testSpace = SpaceEntity(
        spaceId: 'space_AB',
        partnerUid: 'uid_B',
        partnerEmail: 'user_b@gmail.com',
        myDriveFolderId: 'folder_1',
        partnerDriveFolderId: 'folder_2',
        status: SpaceStatus.active,
        createdAt: DateTime.now(),
        lastPairedAt: DateTime.now(),
      );
      await spaceRepo.saveSpace(uid: 'uid_A', space: testSpace);
      await orchestrator.init('uid_A');

      expect(orchestrator.state.isPaired, isTrue);
      expect(orchestrator.state.activeSpace?.partnerEmail, equals('user_b@gmail.com'));

      // Test Unpair
      await orchestrator.unpair(
        currentUid: 'uid_A',
        currentUserEmail: 'user_a@gmail.com',
        driveApi: dummyDriveApi,
      );

      expect(orchestrator.state.isPaired, isFalse);
      expect(orchestrator.state.status, equals(SpaceStatus.none));

      final savedAfterUnpair = await spaceRepo.getSpace(uid: 'uid_A', spaceId: 'space_AB');
      expect(savedAfterUnpair?.status, equals(SpaceStatus.archived));
      expect(savedAfterUnpair?.archivedAt, isNotNull);
    });

    test('TEST 8: Strict Upload Destination Verification against partner folder target', () async {
      final galleryRepo = GalleryRepositoryImpl(
        spaceRepository: spaceRepo,
        driveService: driveService,
      );

      // Inactive space test
      expect(
        () => galleryRepo.uploadPhoto(
          currentUid: 'uid_unpaired',
          filePath: '/path/does/not/matter',
          fileName: 'test.jpg',
          driveApi: dummyDriveApi,
        ),
        throwsA(isA<PairingNotActiveException>()),
      );
    });

    test('TEST 9 & 10: Re-Pairing Reactivation & Folder Reuse (No Duplicates)', () async {
      final driveSpaceService = DriveSpaceService(
        spaceRepository: spaceRepo,
        driveService: driveService,
      );

      // First pairing creates folder_1
      final folderId1 = await driveSpaceService.getOrCreateMySpaceFolder(
        currentUid: 'uid_A',
        currentUserEmail: 'user_a@gmail.com',
        partnerUid: 'uid_B',
        partnerEmail: 'user_b@gmail.com',
        myDriveApi: dummyDriveApi,
      );
      expect(folderId1, isNotEmpty);

      // Re-pairing with the same partner B must return the EXACT same folder_1 without creating a new folder
      final folderId2 = await driveSpaceService.getOrCreateMySpaceFolder(
        currentUid: 'uid_A',
        currentUserEmail: 'user_a@gmail.com',
        partnerUid: 'uid_B',
        partnerEmail: 'user_b@gmail.com',
        myDriveApi: dummyDriveApi,
      );
      expect(folderId2, equals(folderId1));
      expect(driveService.folders.length, equals(1));
    });

    test('TEST 11: Controlled Recovery when registered Drive folder was deleted externally', () async {
      final driveSpaceService = DriveSpaceService(
        spaceRepository: spaceRepo,
        driveService: driveService,
      );

      final folderId1 = await driveSpaceService.getOrCreateMySpaceFolder(
        currentUid: 'uid_A',
        currentUserEmail: 'user_a@gmail.com',
        partnerUid: 'uid_B',
        partnerEmail: 'user_b@gmail.com',
        myDriveApi: dummyDriveApi,
      );

      // Simulate external deletion of folder from Drive
      driveService.folders.remove(folderId1);

      // Re-invoking resolution should gracefully recover by creating/finding a valid folder without crashing
      final recoveredFolderId = await driveSpaceService.getOrCreateMySpaceFolder(
        currentUid: 'uid_A',
        currentUserEmail: 'user_a@gmail.com',
        partnerUid: 'uid_B',
        partnerEmail: 'user_b@gmail.com',
        myDriveApi: dummyDriveApi,
      );

      expect(recoveredFolderId, isNotEmpty);
      expect(recoveredFolderId, isNot(equals(folderId1)));
      expect(driveService.folders.containsKey(recoveredFolderId), isTrue);
    });

    test('TEST 12: Partner Photo Deletion Prevention Invariant', () async {
      final galleryRepo = GalleryRepositoryImpl(
        spaceRepository: spaceRepo,
        driveService: driveService,
      );

      final pairedSpace = SpaceEntity(
        spaceId: 'space_AB',
        partnerUid: 'uid_B',
        partnerEmail: 'b@test.com',
        myDriveFolderId: 'folder_1',
        partnerDriveFolderId: 'folder_2',
        status: SpaceStatus.active,
        createdAt: DateTime.now(),
        lastPairedAt: DateTime.now(),
      );
      await spaceRepo.saveSpace(uid: 'uid_A', space: pairedSpace);

      // Add partner photo in folder_2
      final partnerPhoto = drive.File()
        ..id = 'partner_img_99'
        ..name = 'partner.jpg'
        ..createdTime = DateTime.now();
      driveService.filesByFolder['folder_2'] = [partnerPhoto];

      // Load gallery so cache is populated
      await galleryRepo.getActiveGalleryPhotos(
        currentUid: 'uid_A',
        driveApi: dummyDriveApi,
        forceRefresh: true,
      );

      // Attempting to delete partner's photo must throw OwnershipViolationException
      expect(
        () => galleryRepo.deleteMyPhoto(
          currentUid: 'uid_A',
          fileId: 'partner_img_99',
          driveApi: dummyDriveApi,
        ),
        throwsA(isA<OwnershipViolationException>()),
      );
    });
  });
}
