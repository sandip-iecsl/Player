import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/audio_provider.dart';
import '../providers/connectivity_provider.dart';
import '../widgets/full_player.dart';
import '../widgets/floating_mini_player.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'room_screen.dart';
import 'local_music_screen.dart';
import '../providers/lock_provider.dart';
import '../providers/aura_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/permission_service.dart';
import '../../data/services/local_chat_service.dart';
import '../../data/services/user_registration_service.dart';
import '../providers/theme_provider.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> with WidgetsBindingObserver {
  final PanelController _panelController = PanelController();
  int _currentIndex = 0;
  bool _isShowingNameDialog = false;
  bool _nameDialogCompleted = false;
  bool _isPanelOpen = false; // Track panel state
  // Key to access SearchScreen state for clearing on tab change
  final GlobalKey<SearchScreenState> _searchKey = GlobalKey<SearchScreenState>();

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  late final List<Widget> _screens = [
    _TabNavigator(root: const HomeScreen(), navigatorKey: _navigatorKeys[0]),
    _TabNavigator(root: SearchScreen(key: _searchKey), navigatorKey: _navigatorKeys[1]),
    _TabNavigator(root: const LibraryScreen(), navigatorKey: _navigatorKeys[2]),
    _TabNavigator(root: const RoomScreen(), navigatorKey: _navigatorKeys[3]),
    _TabNavigator(root: const LocalMusicScreen(), navigatorKey: _navigatorKeys[4]),
  ];

  // Platform channels for screen state
  static const screenChannel = MethodChannel('aura_player/screen_state');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialConnectivity();
    
    // Setup native screen state listener
    _setupScreenStateListener();
    
    // Request notification and mic permissions after first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PermissionService.requestAudioPermissions();
      
      // Re-sync full profile on every launch (returning user) — updates
      // lastActive, status, device meta, and ensures discoverability
      final name = ref.read(lockProvider).userName;
      if (name != null && name.isNotEmpty) {
        UserRegistrationService().registerOrUpdate(name);
      }
    });
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      if (connectivityResults.contains(ConnectivityResult.none)) {
        if (mounted) {
          setState(() {
            _currentIndex = 2; // Route to Library on startup if offline
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _setupScreenStateListener() async {
    try {
      // Register native screen state listener on Android
      await screenChannel.invokeMethod('registerScreenStateListener');
      debugPrint('[MainScreen] ✅ Screen state listener registered');
      
      // Setup method call handler to receive screen state changes from native
      screenChannel.setMethodCallHandler((MethodCall call) async {
        debugPrint('[MainScreen] 📱 Method call from native: ${call.method}');
        
        if (call.method == 'onScreenStateChanged') {
          final isScreenOn = call.arguments['isScreenOn'] as bool?;
          final isAODActive = call.arguments['isAODActive'] as bool? ?? false;
          
          debugPrint('[MainScreen] 📱 Screen state: on=$isScreenOn, AOD=$isAODActive');
          
          if (isScreenOn != null) {
            ref.read(audioServiceProvider).handleScreenStateChange(
              isScreenOn: isScreenOn,
              isAODActive: isAODActive,
            );
          }
        } else if (call.method == 'onAODStateChanged') {
          final isScreenOn = call.arguments['isScreenOn'] as bool? ?? false;
          final isAODActive = call.arguments['isAODActive'] as bool?;
          
          debugPrint('[MainScreen] 🔄 AOD state: on=$isScreenOn, AOD=$isAODActive');
          
          if (isAODActive != null) {
            ref.read(audioServiceProvider).handleScreenStateChange(
              isScreenOn: isScreenOn,
              isAODActive: isAODActive,
            );
          }
        }
      });
    } catch (e) {
      debugPrint('[MainScreen] ⚠️ Failed to setup screen state listener: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[MainScreen] 📱 App lifecycle state changed: $state');
    
    // Trigger presence online/offline status lifecycles and offline message queuing listeners
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached || state == AppLifecycleState.inactive) {
      debugPrint('[MainScreen] ⏸️ App paused/inactive - marking user presence offline');
      LocalChatService().stopHeartbeat();
      LocalChatService().stopPendingQueueListener();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[MainScreen] ▶️ App resumed - restoring user presence heartbeats');
      LocalChatService().startHeartbeat();
      LocalChatService().listenToPendingQueue();
    }
  }

  DateTime? _lastBackPressTime;

  Future<bool> _onWillPop() async {
    // If full player panel is open, close it first
    try {
      if (_panelController.isPanelOpen) {
        _panelController.close();
        return false;
      }
    } catch (_) {}
    
    // Check if the current tab's navigator can pop
    final navigator = _navigatorKeys[_currentIndex].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return false;
    }

    // If not on home tab, navigate to home
    if (_currentIndex != 0) {
      if (mounted) setState(() => _currentIndex = 0);
      return false;
    }

    // Double-tap back press to confirm exit and prevent accidental back gestures
    final now = DateTime.now();
    if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    SystemNavigator.pop();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeModeProvider);
    ref.watch(themeColorProvider);
    final currentSong = ref.watch(currentSongProvider).valueOrNull;
    final lockState = ref.watch(lockProvider);
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;
    ref.watch(auraProvider); // Initialize Heartbeat service

    // Removed LockScreen intercept
    // Prompt for username if unlocked but no name exists
    if (lockState.isInitialized && lockState.userName == null && !_nameDialogCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          _showNameSetupDialog(context, ref);
        }
      });
    }

    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: AppColors.deepSpaceBlack,
        bottomNavigationBar: isKeyboardOpen
            ? null
            : BottomNavigationBar(
                currentIndex: _currentIndex,
          onTap: (index) {
            try {
              if (_panelController.isAttached && _panelController.isPanelOpen) {
                _panelController.close();
              }
            } catch (_) {}
            if (_currentIndex == 1 && index != 1) {
              _searchKey.currentState?.clearState();
            }
            if (_currentIndex == index) {
              _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
            } else {
              setState(() => _currentIndex = index);
            }
          },
          selectedItemColor: AppColors.neonPink,
          unselectedItemColor: AppColors.textSecondary,
          selectedLabelStyle: const TextStyle(fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.deepSpaceBlack,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
            BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Library'),
            BottomNavigationBarItem(icon: Icon(Icons.speaker_group), label: 'Room'),
            BottomNavigationBarItem(icon: Icon(Icons.folder_rounded), label: 'Local'),
          ],
        ),
        // Use body as a Stack so the floating mini player overlays everything
        body: Stack(
          children: [
            // ── Full-screen player (SlidingUpPanel) ──────────────────
            SlidingUpPanel(
              controller: _panelController,
              maxHeight: MediaQuery.of(context).size.height,
              minHeight: 0,
              borderRadius: null,
              color: Colors.transparent,
              backdropEnabled: false,
              renderPanelSheet: false,
              onPanelSlide: (position) {
                // position: 0.0 = closed, 1.0 = fully open
                // Hide mini player when panel starts opening (> 0.1)
                final shouldHide = position > 0.1;
                if (shouldHide != _isPanelOpen) {
                  setState(() => _isPanelOpen = shouldHide);
                }
              },
              panel: currentSong != null
                  ? FullPlayer(
                      currentSong: currentSong,
                      onClose: () => _panelController.close(),
                    )
                  : const SizedBox.shrink(),
              body: Padding(
                // Reserve space at bottom for mini player — hide when keyboard is open
                padding: EdgeInsets.only(
                  bottom: currentSong != null && !isKeyboardOpen ? 90 : 0,
                ),
                child: Stack(
                  children: [
                    IndexedStack(
                      index: _currentIndex,
                      children: _screens,
                    ),
                    if (!isOnline && (_currentIndex == 0 || _currentIndex == 1 || _currentIndex == 3))
                      Positioned.fill(
                        child: Container(
                          color: AppColors.deepSpaceBlack, // Opaque background
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 80),
                                const SizedBox(height: 16),
                                const Text(
                                  'No Internet Connection',
                                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'You are currently offline.',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton.icon(
                                  onPressed: () => setState(() => _currentIndex = 2), // Go to Library
                                  icon: const Icon(Icons.library_music_rounded, color: Colors.black),
                                  label: const Text('Go to Library', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.neonCoral,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Floating mini player — sits above bottom nav — hide when keyboard is open ──────────
            if (currentSong != null)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                left: 0,
                right: 0,
                bottom: _isPanelOpen || isKeyboardOpen ? -100 : 2, // slide down when panel or keyboard is open
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _isPanelOpen || isKeyboardOpen ? 0.0 : 1.0,
                  child: FloatingMiniPlayer(
                    key: ValueKey(currentSong.id),
                    song: currentSong,
                    onTap: () => _panelController.open(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showNameSetupDialog(BuildContext context, WidgetRef ref) {
    if (_isShowingNameDialog) return;
    _isShowingNameDialog = true;

    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          backgroundColor: AppColors.deepSpaceBlackLight,
          title: const Text('Welcome to Aura', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What should we call you?', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Enter your name',
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  setState(() {
                    _nameDialogCompleted = true;
                  });
                  ref.read(lockProvider.notifier).setUserName(name);
                  LocalChatService().registerUser(name);
                  Navigator.of(ctx).pop();
                }
              },
              child: Text('Save', style: TextStyle(color: AppColors.neonPink, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    ).then((_) => _isShowingNameDialog = false);
  }
}

class _TabNavigator extends StatelessWidget {
  final Widget root;
  final GlobalKey<NavigatorState> navigatorKey;

  const _TabNavigator({required this.root, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute(builder: (context) => root),
    );
  }
}