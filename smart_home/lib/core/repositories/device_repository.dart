import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device_model.dart';
import '../services/firebase_service.dart';

class DeviceRepository {
  final _fs = FirebaseService.instance;

  /// Real-time stream of all relay states from Firebase RTDB.
  Stream<List<DeviceModel>> watchDevices() {
    return _fs.relaysStream.map((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) return DeviceModel.defaults();
      return List.generate(10, (i) {
        final id = 'relay${i + 1}';
        final raw = data[id] as Map?;
        if (raw == null) return DeviceModel.defaults()[i];
        return DeviceModel.fromMap(raw, id);
      });
    });
  }

  Future<void> toggleDevice(String relayId, bool state) =>
      _fs.toggleRelay(relayId, state);

  Future<void> updateDevice(String relayId, Map<String, dynamic> data) =>
      _fs.updateRelayData(relayId, data);

  Future<void> resetDevice(String relayId) => updateDevice(relayId, {
        'state': false,
        'favorite': false,
        'visible': true,
      });

  /// Initialize RTDB with defaults if empty
  Future<void> initDefaults() async {
    final snap = await _fs.relaysRef.get();
    if (!snap.exists) {
      final defaults = DeviceModel.defaults();
      for (final d in defaults) {
        await _fs.relayRef(d.id).set(d.toMap());
      }
    }
  }
}

final deviceRepositoryProvider = Provider<DeviceRepository>(_=> DeviceRepository());

final devicesStreamProvider = StreamProvider<List<DeviceModel>>((ref) {
  return ref.watch(deviceRepositoryProvider).watchDevices();
});
