import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'data/services/audio_service.dart';
import 'presentation/screens/main_screen.dart';
import 'presentation/providers/theme_provider.dart';
import 'data/services/cloud_sync_service.dart';
import 'data/services/fcm_token_service.dart';
import 'data/services/hive_cache_manager.dart';
import 'data/services/search_enhancer.dart';
import 'core/kernel/aura_application.dart';
/// Global navigator key — used by PlaylistDialogs to show dialogs
/// from any context (sheets, full player, etc.) without context-lifecycle issues.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error guard ───────────────────────────────────────────────────
  // Catches unhandled Flutter framework errors (e.g. native ExoPlayer exceptions
  // surfaced via platform channels) before they can terminate the process.
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[GlobalError] Flutter error: ${details.exception}');
    debugPrint('[GlobalError] Stack: ${details.stack}');
  };

  // Catches unhandled async Dart errors on the root isolate (e.g. from just_audio
  // internal stream listeners) that would otherwise crash the app.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[GlobalError] Uncaught async error: $error');
    debugPrint('[GlobalError] Stack: $stack');
    return true; // Return true = error is handled, do NOT terminate
  };

  await dotenv.load(fileName: '.env');
  await Hive.initFlutter();
  
  // Open recommendation engine boxes
  await Hive.openBox('track_transitions');
  await Hive.openBox('listening_history');
  
  // Offline storage
  await Hive.openBox('offline_songs');
  
  // Advanced Architecture Boxes
  await HiveCacheManager.initBox();
  await Hive.openBox('firebase_offline_sync_box');
  await Hive.openBox('ml_training_box');
  
  // Chat and Admin Module Boxes
  await Hive.openBox<String>('secure_chat_messages');
  await Hive.openBox<String>('secure_admin_audits');

  // YouTube Imports & Extractor Cache
  await Hive.openBox('yt_imports_cache');




  // Initialize Firebase (safely, in case user hasn't run flutterfire configure yet)
  try {
    await Firebase.initializeApp(
      options: kIsWeb
          ? FirebaseOptions(
              apiKey: dotenv.env['FIREBASE_API_KEY'] ?? '',
              appId: dotenv.env['FIREBASE_APP_ID'] ?? '',
              messagingSenderId: dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '',
              projectId: dotenv.env['FIREBASE_PROJECT_ID'] ?? '',
              authDomain: dotenv.env['FIREBASE_AUTH_DOMAIN'] ?? '',
              storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? '',
            )
          : null,
    );
    debugPrint('🔥 Firebase initialized successfully for Global Engine.');
    
    // Bootstrap the central AuraApplication Kernel
    await AuraApplication().bootstrap();
    
    // Initialize Cloud Sync Service for anonymous auth and data restore
    // We don't await this to prevent network hangs from keeping the app stuck on splash
    CloudSyncService().init().catchError((e) => debugPrint('CloudSync error: $e'));

    // Sync ML Engine Synonyms
    SearchEnhancer.syncFromFirestore();
    
    // Init FCM token service
    // We don't await this either for the same reason
    FcmTokenService().init().catchError((e) => debugPrint('FCM error: $e'));
  } catch (e) {
    debugPrint('⚠️ Firebase not configured natively yet. Global engine will skip sync: $e');
  }

  try {
    audioHandler = await AudioService.init(
      builder: () => AudioServiceHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.free_play.audio',
        androidNotificationChannelName: 'Aura Player Music',
        androidNotificationChannelDescription: 'Music playback controls',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidNotificationClickStartsActivity: true,
        androidNotificationIcon: 'mipmap/launcher_icon',
        androidShowNotificationBadge: true,
        notificationColor: Color(0xFFE91E63),
        fastForwardInterval: Duration(seconds: 15),
        rewindInterval: Duration(seconds: 15),
        preloadArtwork: true,
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

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Aura Player',
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      themeMode: themeMode,
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
