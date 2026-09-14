import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/space.dart';
import '../../domain/repositories/space_repository.dart';
import '../models/space_model.dart';

/// Implementation of [SpaceRepository] backed by Cloud Firestore.
/// Path: `user_profiles/{uid}/spaces/{spaceId}`
class SpaceRepositoryImpl implements SpaceRepository {
  final FirebaseFirestore _firestore;

  SpaceRepositoryImpl({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _spacesCollection(String uid) {
    return _firestore.collection('user_profiles').doc(uid).collection('spaces');
  }

  @override
  Future<SpaceEntity?> getSpace({
    required String uid,
    required String spaceId,
  }) async {
    try {
      final doc = await _spacesCollection(uid).doc(spaceId).get();
      if (!doc.exists || doc.data() == null) return null;
      return SpaceModel.fromFirestore(doc).toEntity();
    } catch (e) {
      debugPrint('[SpaceRepo] ❌ Error getting space $spaceId: $e');
      return null;
    }
  }

  @override
  Future<SpaceEntity?> getActiveSpace({required String uid}) async {
    try {
      final query = await _spacesCollection(uid)
          .where('status', isEqualTo: SpaceStatus.active.name)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;
      return SpaceModel.fromFirestore(query.docs.first).toEntity();
    } catch (e) {
      debugPrint('[SpaceRepo] ❌ Error getting active space for $uid: $e');
      return null;
    }
  }

  @override
  Future<void> saveSpace({
    required String uid,
    required SpaceEntity space,
  }) async {
    try {
      final model = SpaceModel.fromEntity(space);
      await _spacesCollection(uid)
          .doc(space.spaceId)
          .set(model.toFirestore(), SetOptions(merge: true));
      debugPrint('[SpaceRepo] 💾 Saved space ${space.spaceId} with status ${space.status.name}');
    } catch (e) {
      debugPrint('[SpaceRepo] ❌ Error saving space ${space.spaceId}: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateSpaceStatus({
    required String uid,
    required String spaceId,
    required SpaceStatus status,
    DateTime? lastPairedAt,
    DateTime? archivedAt,
  }) async {
    try {
      final Map<String, dynamic> update = {
        'status': status.name,
      };

      if (lastPairedAt != null) {
        update['last_paired_at'] = Timestamp.fromDate(lastPairedAt);
      }
      if (archivedAt != null) {
        update['archived_at'] = Timestamp.fromDate(archivedAt);
      }

      await _spacesCollection(uid).doc(spaceId).update(update);
      debugPrint('[SpaceRepo] 🔄 Updated space $spaceId status to: ${status.name}');
    } catch (e) {
      debugPrint('[SpaceRepo] ❌ Error updating space status: $e');
      rethrow;
    }
  }

  @override
  Future<void> updatePartnerFolderId({
    required String uid,
    required String spaceId,
    required String partnerFolderId,
  }) async {
    try {
      await _spacesCollection(uid).doc(spaceId).update({
        'partner_drive_folder_id': partnerFolderId,
      });
      debugPrint('[SpaceRepo] 🤝 Updated partner folder ID for space: $spaceId');
    } catch (e) {
      debugPrint('[SpaceRepo] ❌ Error updating partner folder ID: $e');
      rethrow;
    }
  }

  @override
  Future<List<SpaceEntity>> listSpaces({required String uid}) async {
    try {
      final snapshot = await _spacesCollection(uid).get();
      return snapshot.docs
          .map((doc) => SpaceModel.fromFirestore(doc).toEntity())
          .toList();
    } catch (e) {
      debugPrint('[SpaceRepo] ❌ Error listing spaces for $uid: $e');
      return [];
    }
  }

  @override
  Stream<SpaceEntity?> watchActiveSpace({required String uid}) {
    return _spacesCollection(uid)
        .where('status', isEqualTo: SpaceStatus.active.name)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return SpaceModel.fromFirestore(snapshot.docs.first).toEntity();
    });
  }
}
