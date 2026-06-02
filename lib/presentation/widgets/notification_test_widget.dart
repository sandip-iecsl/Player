import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/permission_service.dart';
import '../../data/services/audio_service.dart' show audioHandler;

class NotificationTestWidget extends ConsumerStatefulWidget {
  const NotificationTestWidget({super.key});

  @override
  ConsumerState<NotificationTestWidget> createState() => _NotificationTestWidgetState();
}

class _NotificationTestWidgetState extends ConsumerState<NotificationTestWidget> {
  bool _permissionGranted = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _isChecking = true);
    final granted = await PermissionService.checkNotificationPermission();
    setState(() {
      _permissionGranted = granted;
      _isChecking = false;
    });
  }

  Future<void> _requestPermissions() async {
    setState(() => _isChecking = true);
    final granted = await PermissionService.requestNotificationPermission();
    setState(() {
      _permissionGranted = granted;
      _isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Notification Controls Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _permissionGranted ? Icons.check_circle : Icons.error,
                  color: _permissionGranted ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _permissionGranted 
                    ? 'Notification permission granted' 
                    : 'Notification permission required',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_permissionGranted) ...[
              ElevatedButton(
                onPressed: _isChecking ? null : _requestPermissions,
                child: _isChecking 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Request Permission'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Notification controls won\'t work without this permission on Android 13+',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Test Controls:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => audioHandler.play(),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
                ElevatedButton.icon(
                  onPressed: () => audioHandler.pause(),
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
                ElevatedButton.icon(
                  onPressed: () => audioHandler.skipToNext(),
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Next'),
                ),
                ElevatedButton.icon(
                  onPressed: () => audioHandler.skipToPrevious(),
                  icon: const Icon(Icons.skip_previous),
                  label: const Text('Previous'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'These buttons should work both in-app and from the notification panel',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}