import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'data/services/audio_service.dart';
import 'data/services/permission_service.dart';
import 'data/services/screen_state_service.dart';
import 'presentation/screens/main_screen.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/music_data_providers.dart';
import 'presentation/widgets/screen_state_listener.dart';
import 'config/spotify_config.dart';

/// Global navigator key — used by PlaylistDialogs to show dialogs
/// from any context (sheets, full player, etc.) without context-lifecycle issues.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await Hive.initFlutter();

  // Request notification permissions first
  await PermissionService.requestAudioPermissions();

  // Initialize screen state monitoring for AOD support
  await ScreenStateService.initialize();

  try {
    audioHandler = await AudioService.init(
      builder: () => AudioServiceHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.free_play.audio',
        androidNotificationChannelName: 'Aura Player Music',
        androidNotificationChannelDescription: 'Enhanced music playback controls with always-on display support',
        androidNotificationOngoing: true, // Keep notification persistent for always-on display
        androidStopForegroundOnPause: true, // Allow stopping foreground when paused
        androidNotificationClickStartsActivity: true,
        androidNotificationIcon: 'drawable/ic_notification',
        androidShowNotificationBadge: true,
        notificationColor: Color(0xFF1DB954),
        fastForwardInterval: Duration(seconds: 15),
        rewindInterval: Duration(seconds: 15),
        preloadArtwork: true,
        // Enhanced notification settings for stylish controls and always-on display
        androidResumeOnClick: true,
      ),
    ).timeout(
      const Duration(seconds: 10), // Increased timeout
      onTimeout: () {
        debugPrint('AudioService init timed out - using fallback');
        return AudioServiceHandler();
      },
    );
    
    debugPrint('✅ AudioService initialized successfully');
  } catch (e) {
    debugPrint('❌ AudioService init failed: $e — using fallback');
    audioHandler = AudioServiceHandler();
  }

  runApp(const ProviderScope(child: AuraPlayer()));
}

class AuraPlayer extends ConsumerWidget {
  const AuraPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    // Spotify Client Credentials — auto-managed, no token needed here
    debugPrint('✅ Search: Spotify + Last.fm + JioSaavn enabled');

    return ScreenStateListener(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Aura Player',
        theme: ref.watch(lightThemeProvider),
        darkTheme: ref.watch(darkThemeProvider),
        themeMode: themeMode,
        home: const MainScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
