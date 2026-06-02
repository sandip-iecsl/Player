import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import '../providers/audio_provider.dart';
import '../widgets/full_player.dart';
import '../widgets/floating_mini_player.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'room_screen.dart';
import 'lock_screen.dart';
import 'local_music_screen.dart';
import '../providers/lock_provider.dart';
import '../providers/aura_provider.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  final PanelController _panelController = PanelController();
  int _currentIndex = 0;
  bool _isShowingNameDialog = false;
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

    // Direct exit without pop-up as requested
    SystemNavigator.pop();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(currentSongProvider).valueOrNull;
    final lockState = ref.watch(lockProvider);
    ref.watch(auraProvider); // Initialize Heartbeat service

    if (lockState.isLocked) {
      return const LockScreen();
    }

    // Prompt for username if unlocked but no name exists
    if (lockState.userName == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          _showNameSetupDialog(context, ref);
        }
      });
    }

    final bottomNavHeight = 60.0; // approximate bottom nav height

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.black,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            if (_panelController.isPanelOpen) {
              _panelController.close();
            }
            if (_currentIndex == 1 && index != 1) {
              _searchKey.currentState?.clearState();
            }
            if (_currentIndex == index) {
              _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
            } else {
              setState(() => _currentIndex = index);
            }
          },
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: const TextStyle(fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.black,
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
                // Reserve space at bottom for mini player  
                padding: EdgeInsets.only(
                  bottom: currentSong != null ? 86 : 0,
                ),
                child: IndexedStack(
                  index: _currentIndex,
                  children: _screens,
                ),
              ),
            ),

            // ── Floating mini player — sits above bottom nav ──────────
            if (currentSong != null)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                left: 0,
                right: 0,
                bottom: _isPanelOpen ? -100 : bottomNavHeight + 4, // slide down when panel opens
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _isPanelOpen ? 0.0 : 1.0,
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
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Welcome to Aura', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('What should we call you?', style: TextStyle(color: Colors.grey)),
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
                  ref.read(lockProvider.notifier).setUserName(name);
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('Save', style: TextStyle(color: Color(0xFF1DB954), fontWeight: FontWeight.bold, fontSize: 16)),
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
