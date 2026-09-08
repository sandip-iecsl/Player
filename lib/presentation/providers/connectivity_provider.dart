import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider to check if the device is currently online.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();

  // Yield initial state
  final initialStatus = await connectivity.checkConnectivity();
  yield !initialStatus.contains(ConnectivityResult.none);

  // Yield changes
  await for (final status in connectivity.onConnectivityChanged) {
    yield !status.contains(ConnectivityResult.none);
  }
});
