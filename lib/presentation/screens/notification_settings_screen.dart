import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/notification_controller_provider.dart';
import '../widgets/enhanced_notification_controller.dart';
import '../../domain/entities/song.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationControllerSettingsProvider);
    final settingsNotifier = ref.read(notificationControllerSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Controls'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview Section
            const Text(
              'Preview',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Preview of the notification controller
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: EnhancedNotificationController(
                currentSong: _getSampleSong(),
                isCompact: settings.style == NotificationStyle.compact,
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Settings Section
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Enhanced Controller Toggle
            _buildSettingTile(
              title: 'Enhanced Controller',
              subtitle: 'Use stylish animated notification controls',
              value: settings.useEnhancedController,
              onChanged: (_) => settingsNotifier.toggleEnhancedController(),
            ),
            
            // Beat Response Toggle
            _buildSettingTile(
              title: 'Beat Response',
              subtitle: 'Animate controls based on music rhythm',
              value: settings.enableBeatResponse,
              onChanged: (_) => settingsNotifier.toggleBeatResponse(),
            ),

            
            // Animations Toggle
            _buildSettingTile(
              title: 'Animations',
              subtitle: 'Enable smooth transitions and effects',
              value: settings.enableAnimations,
              onChanged: (_) => settingsNotifier.toggleAnimations(),
            ),
            
            const SizedBox(height: 24),
            
            // Style Selection
            const Text(
              'Style',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            
            _buildStyleSelector(context, ref, settings, settingsNotifier),
            
            const SizedBox(height: 24),
            
            // Animation Intensity Slider
            const Text(
              'Animation Intensity',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            
            Slider(
              value: settings.animationIntensity,
              onChanged: settingsNotifier.setAnimationIntensity,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              label: '${(settings.animationIntensity * 100).round()}%',
              activeColor: const Color(0xFF1DB954),
            ),
            
            const SizedBox(height: 24),
            
            // Custom Accent Color
            const Text(
              'Accent Color',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            
            _buildColorSelector(context, ref, settings, settingsNotifier),
            
            const SizedBox(height: 32),
            
            // Info Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue.shade300,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'About Enhanced Controls',
                        style: TextStyle(
                          color: Colors.blue.shade300,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enhanced notification controls provide a more immersive music experience with:\n'
                    '• Beat-responsive animations\n'
                    '• Always-on display support\n'
                    '• Customizable styles and colors\n'
                    '• Smooth transitions and effects',
                    style: TextStyle(
                      color: Colors.blue.shade200,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 13,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFF1DB954),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildStyleSelector(
    BuildContext context,
    WidgetRef ref,
    NotificationControllerSettings settings,
    NotificationControllerSettingsNotifier settingsNotifier,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: NotificationStyle.values.map((style) {
        final isSelected = settings.style == style;
        return GestureDetector(
          onTap: () => settingsNotifier.setStyle(style),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected 
                  ? const Color(0xFF1DB954).withOpacity(0.2)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected 
                    ? const Color(0xFF1DB954)
                    : Colors.grey.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Text(
              _getStyleName(style),
              style: TextStyle(
                color: isSelected 
                    ? const Color(0xFF1DB954)
                    : Colors.white,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildColorSelector(
    BuildContext context,
    WidgetRef ref,
    NotificationControllerSettings settings,
    NotificationControllerSettingsNotifier settingsNotifier,
  ) {
    final colors = [
      null, // Auto (from album art)
      const Color(0xFF1DB954), // Spotify Green
      Colors.blue,
      Colors.purple,
      Colors.orange,
      Colors.red,
      Colors.pink,
      Colors.teal,
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: colors.map((color) {
        final isSelected = settings.customAccentColor == color;
        return GestureDetector(
          onTap: () => settingsNotifier.setCustomAccentColor(color),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color ?? Colors.grey.shade700,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2,
              ),
            ),
            child: color == null
                ? const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 20,
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }

  String _getStyleName(NotificationStyle style) {
    switch (style) {
      case NotificationStyle.enhanced:
        return 'Enhanced';
      case NotificationStyle.compact:
        return 'Compact';
      case NotificationStyle.minimal:
        return 'Minimal';
      case NotificationStyle.visualizer:
        return 'Visualizer';
    }
  }

  Song _getSampleSong() {
    return Song(
      id: 'sample',
      title: 'Sample Song',
      artist: 'Sample Artist',
      album: 'Sample Album',
      duration: const Duration(minutes: 3, seconds: 30),
      albumArt: 'https://via.placeholder.com/300x300/1DB954/FFFFFF?text=♪',
    );
  }
}