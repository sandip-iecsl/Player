import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device_model.dart';
import '../repositories/device_repository.dart';
import '../services/firebase_service.dart';
import 'notification_provider.dart';

class DeviceNotifier extends Notifier<List<DeviceModel>> {
  @override
  List<DeviceModel> build() => DeviceModel.defaults();

  Future<void> toggle(DeviceModel device) async {
    final newState = !device.state;
    // Optimistic UI update
    state = state.map((d) => d.id == device.id ? d.copyWith(state: newState) : d).toList();
    try {
      await ref.read(deviceRepositoryProvider).toggleDevice(device.id, newState);
      // Log audit
      await FirebaseService.instance.logAudit(
        'toggle_device',
        details: {'device': device.name, 'state': newState},
      );
      // Local notification
      ref.read(notificationServiceProvider).showDeviceToggle(device.name, newState);
    } catch (_) {
      // Revert on failure
      state = state.map((d) => d.id == device.id ? d.copyWith(state: device.state) : d).toList();
    }
  }

  Future<void> updateDevice(DeviceModel device) async {
    await ref.read(deviceRepositoryProvider).updateDevice(device.id, device.toMap());
    state = state.map((d) => d.id == device.id ? device : d).toList();
  }

  Future<void> resetDevice(String relayId) async {
    await ref.read(deviceRepositoryProvider).resetDevice(relayId);
  }

  void updateFromStream(List<DeviceModel> devices) {
    state = devices;
  }
}

final deviceNotifierProvider =
    NotifierProvider<DeviceNotifier, List<DeviceModel>>(() => DeviceNotifier());

// Filtered devices by room
final devicesByRoomProvider =
    Provider.family<List<DeviceModel>, String>((ref, room) {
  final devices = ref.watch(devicesStreamProvider).value ?? [];
  if (room == 'All') return devices.where((d) => d.visible).toList();
  return devices.where((d) => d.room == room && d.visible).toList();
});

// Online device count
final onlineDeviceCountProvider = Provider<int>((ref) {
  final devices = ref.watch(devicesStreamProvider).value ?? [];
  return devices.where((d) => d.state).length;
});

// Favorite devices
final favoriteDevicesProvider = Provider<List<DeviceModel>>((ref) {
  final devices = ref.watch(devicesStreamProvider).value ?? [];
  return devices.where((d) => d.favorite && d.visible).toList();
});
