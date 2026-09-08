import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room_model.dart';
import '../services/firebase_service.dart';

class RoomRepository {
  final _fs = FirebaseService.instance;

  Stream<List<RoomModel>> watchRooms() =>
      _fs.roomsRef.orderBy('order').snapshots().map(
            (s) => s.docs.map((d) => RoomModel.fromFirestore(d.data(), d.id)).toList(),
          );

  Future<void> addRoom(RoomModel room) =>
      _fs.roomsRef.doc(room.id).set(room.toFirestore());

  Future<void> updateRoom(String id, Map<String, dynamic> data) =>
      _fs.roomsRef.doc(id).update(data);

  Future<void> deleteRoom(String id) => _fs.roomsRef.doc(id).delete();

  Future<void> initDefaults() async {
    final snap = await _fs.roomsRef.limit(1).get();
    if (snap.docs.isEmpty) {
      for (final r in RoomModel.defaults()) {
        await _fs.roomsRef.doc(r.id).set(r.toFirestore());
      }
    }
  }
}

final roomRepositoryProvider = Provider<RoomRepository>(_=> RoomRepository());

final roomsStreamProvider = StreamProvider<List<RoomModel>>((ref) {
  return ref.watch(roomRepositoryProvider).watchRooms();
});
