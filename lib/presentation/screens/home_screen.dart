import 'dart:math';
import 'package:flutter/material.dart';
import 'secret_console_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/services/audio_service.dart'; // PlaybackContext
import '../../data/services/spotify_client_service.dart';
import '../providers/music_data_providers.dart';
import '../providers/audio_provider.dart';
import '../providers/history_provider.dart';
import '../../domain/entities/song.dart';
import '../../core/config/app_config.dart';
import '../../data/datasources/remote/multi_source_aggregator.dart';
import 'package:dio/dio.dart';
import 'playlist_screen.dart';
import '../widgets/playlist_dialogs.dart';
import '../../core/constants/app_colors.dart';
import '../../features/admin/engines/security_engine.dart';
import '../widgets/import_link_modal.dart';

/// Decodes HTML entities in song titles from JioSaavn
/// e.g. &quot; → " , &amp; → & , &#039; → '
String _decodeHtml(String input) {
  return input
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');
}

/// Opens a URL in the external browser/app
Future<void> _openUrl(Uri uri) async {
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ── Section definition ─────────────────────────────────────────────────────

class _SectionDef {
  final String emoji;
  final String title;
  final String query;
  final bool vertical;
  const _SectionDef(this.emoji, this.title, this.query,
      {this.vertical = false});
}

class _LoadedSection {
  final String title;
  final List<Song> songs;
  final bool vertical;
  _LoadedSection(
      {required this.title, required this.songs, required this.vertical});
}

// ── 60+ rotating section definitions ─────────────────────────────────────────
// Priority: Hindi > Bengali > Bhojpuri > Punjabi > others

const _allSections = [
  _SectionDef('💕', 'Romantic Hindi', 'romantic hindi songs arijit'),
  _SectionDef('🔥', 'Bollywood Party', 'bollywood party hits dance 2025'),
  _SectionDef('😢', 'Sad Songs', 'sad hindi emotional breakup songs'),
  _SectionDef('🎤', 'Arijit Singh', 'arijit singh'),
  _SectionDef('🌅', 'Morning Vibes', 'morning hindi'),
  _SectionDef('🌙', 'Chill Nights', 'chill hindi'),
  _SectionDef('🕺', 'Dance Floor', 'dance hindi'),
  _SectionDef('🙏', 'Devotional', 'bhakti'),
  _SectionDef('🎵', 'Old Is Gold', 'kishore kumar'),
  _SectionDef('💪', 'Workout', 'workout hindi'),
  _SectionDef('🌧', 'Monsoon Mood', 'monsoon hindi'),
  _SectionDef('🎸', 'Indie Hindi', 'indie hindi'),
  _SectionDef('👑', 'Neha Kakkar', 'neha kakkar'),
  _SectionDef('🎻', 'Classical Fusion', 'indian classical'),
  _SectionDef('💃', 'Bhangra Mix', 'bhangra'),
  _SectionDef('🏡', 'Desi Vibes', 'guru randhawa'),
  _SectionDef('🎙', 'Rap Hindi', 'hindi rap'),
  _SectionDef('❤️', 'Love Ballads', 'love hindi'),
  _SectionDef('🌺', 'Bengali Songs', 'bengali modern', vertical: true),
  _SectionDef('🥁', 'Bhojpuri Hits', 'bhojpuri pawan', vertical: true),
  _SectionDef('🌟', 'New Releases', 'new hindi'),
  _SectionDef('🎬', 'Bollywood Hits', 'bollywood hits'),
  _SectionDef('🎶', 'Melody Mix', 'melodious hindi'),
  _SectionDef('🏄', 'Summer Hits', 'summer hindi'),
  _SectionDef('📻', 'Radio Top 10', 'top 10 hindi'),
  _SectionDef('✨', 'Shreya Ghoshal', 'shreya ghoshal', vertical: true),
  _SectionDef('🎉', 'Celebration', 'wedding hindi'),
  _SectionDef('🌍', 'Desi Global', 'hindi international'),
  _SectionDef('💙', 'Soft Pop', 'soft hindi pop'),
  _SectionDef('🎷', 'Jazz Fusion', 'jazz indian'),
  _SectionDef('🔊', 'Bass Boost', 'bass hindi'),
  _SectionDef('🌿', 'Meditation', 'meditation indian'),
  _SectionDef('🎤', 'Kumar Sanu Era', 'kumar sanu'),
  _SectionDef('🚗', 'Road Trip', 'road trip hindi'),
  _SectionDef('🌃', 'Night Drive', 'night drive hindi'),
  _SectionDef('🎊', 'Holi Special', 'holi hindi'),
  _SectionDef('🕯', 'Diwali Vibes', 'diwali hindi'),
  _SectionDef('🏔', 'Pahadi Songs', 'pahadi songs', vertical: true),
  _SectionDef('🌊', 'Assamese Folk', 'assamese zubeen', vertical: true),
  _SectionDef('🎵', 'Marathi Hits', 'marathi pop', vertical: true),
  _SectionDef('🎸', 'Punjabi Sufi', 'punjabi sufi'),
  _SectionDef('💫', 'Soulful Sufi', 'rahat fateh ali'),
  _SectionDef('🔥', 'Trending Global', 'trending english'),
  _SectionDef('🧘', 'Yoga Music', 'yoga indian'),
  _SectionDef(
      '🎭', 'Bollywood Drama', 'emotional dramatic bollywood background music'),
  _SectionDef('🎤', 'Mohammed Rafi', 'mohammed rafi classic golden era',
      vertical: true),
  _SectionDef('🌸', 'Spring Songs', 'spring cheerful happy hindi songs'),
  _SectionDef('🚀', 'Future Bass', 'future bass electronic hindi remix'),
  _SectionDef('💖', 'Propose Songs', 'romantic propose love confession hindi'),
  _SectionDef('🎻', 'A.R. Rahman', 'ar rahman best songs hits', vertical: true),
  _SectionDef('🎼', 'Shankar Ehsaan', 'shankar ehsaan loy best songs'),
  _SectionDef('🌙', 'Sleep Music', 'sleep relaxing soft music india'),
  _SectionDef('🎺', 'Retro 80s', '80s bollywood retro classic songs'),
  _SectionDef('🏖', 'Beach Vibes', 'beach tropical chill hindi songs'),
  _SectionDef('💥', 'Item Songs', 'item song bollywood dance 2025'),
  _SectionDef('🎤', 'Jubin Nautiyal', 'jubin nautiyal best romantic songs'),
  _SectionDef('🔮', 'Psychedelic', 'psychedelic trance indian fusion music'),
  _SectionDef('🌻', 'Folk India', 'indian folk music various languages'),
  _SectionDef('🎙', 'Lata Mangeshkar', 'lata mangeshkar golden voice classic',
      vertical: true),
  _SectionDef('🥳', 'Party 2025', 'party banger hindi english remix 2025'),
];

// ── Home Screen ───────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();
  final _loaded = <_LoadedSection>[];
  bool _isLoadingMore = false;
  bool _wave2 = false;
  bool _wave3 = false;
  int _nextIdx = 0;
  late final List<_SectionDef> _queue;
  late final MultiSourceAggregator _agg;

  // Global dedup set — tracks song IDs and normalized titles seen across ALL sections
  final _globalSeenIds = <String>{};
  final _globalSeenTitles = <String>{};

  SharedPreferences? _prefs;
  Map<String, dynamic> _appConfig = {}; // cached from app_config/map_settings
  int _logoTapCount = 0;
  DateTime? _lastLogoTapTime;

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {});
    // Fetch app_config in background so header always shows the live creatorName
    _fetchAppConfig();
  }

  Future<void> _fetchAppConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('map_settings')
          .get(const GetOptions(source: Source.serverAndCache));
      if (doc.exists && doc.data() != null && mounted) {
        setState(() => _appConfig = Map<String, dynamic>.from(doc.data()!));
      }
    } catch (_) {}
  }

  /// Deduplicate songs against the global seen set
  List<Song> _globalDedup(List<Song> songs) {
    final result = <Song>[];
    for (final song in songs) {
      if (song.previewUrl == null || song.previewUrl!.isEmpty) continue;

      final lowerText = '${song.title} ${song.artist}'.toLowerCase();
      if (lowerText.contains('michael jackson') ||
          lowerText.contains('michel jacson') ||
          lowerText.contains('english rap') ||
          lowerText.contains('pista')) {
        continue;
      }

      // Normalize title: lowercase, strip parens/brackets, keep alphanumeric
      final titleKey = song.title
          .toLowerCase()
          .replaceAll(RegExp(r'\(.*?\)'), '')
          .replaceAll(RegExp(r'\[.*?\]'), '')
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (_globalSeenIds.contains(song.id)) continue;
      if (_globalSeenTitles.contains(titleKey)) continue;
      _globalSeenIds.add(song.id);
      _globalSeenTitles.add(titleKey);
      result.add(song);
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _initPrefs();

    // Shuffle the section queue so every session feels fresh
    _queue = List<_SectionDef>.from(_allSections)..shuffle(Random());
    _agg = MultiSourceAggregator(
      dio: Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      )),
      youtubeApiKey: AppConfig.youtubeApiKey,
    );

    // Kick off first 3 sections without blocking each other
    _loadNextSection(0);
    _loadNextSection(1);
    _loadNextSection(2);
    _nextIdx = 3;

    // Staggered provider activation to prevent BLASTBufferQueue overflow
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _wave2 = true);
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _wave3 = true);
    });

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    // Trigger 400px before hitting the bottom — feels seamless
    if (pos.pixels >= pos.maxScrollExtent - 400 && !_isLoadingMore) {
      _loadNextSection();
    }
  }

  Future<void> _loadNextSection([int? forceIndex]) async {
    final sectionIndex = forceIndex ?? _nextIdx;
    if (forceIndex == null) {
      if (_isLoadingMore) return;
      setState(() => _isLoadingMore = true);
      _nextIdx++;
      // Reshuffle queue periodically for variety
      if (_nextIdx % _queue.length == 0) {
        _queue.shuffle(Random());
      }
    }

    final def = _queue[sectionIndex % _queue.length];

    try {
      // Enhanced query with user preference consideration
      String enhancedQuery = def.query;

      // Add contextual enhancement based on time and user history
      final recentlyPlayed = ref.read(recentlyPlayedProvider);
      if (recentlyPlayed.isNotEmpty && Random().nextBool()) {
        final recentArtist =
            recentlyPlayed.first.artist.split(',').first.trim();
        if (def.query.contains('hindi') || def.query.contains('bollywood')) {
          enhancedQuery = '$enhancedQuery $recentArtist';
        }
      }

      final songs =
          await _agg.fetchInfiniteSection(enhancedQuery, sectionIndex);

      // Decode HTML entities in titles
      final cleaned = songs
          .map((s) => Song(
                id: s.id,
                title: _decodeHtml(s.title),
                artist: _decodeHtml(s.artist),
                album: s.album != null ? _decodeHtml(s.album!) : null,
                albumArt: s.albumArt,
                duration: s.duration,
                previewUrl: s.previewUrl,
              ))
          .toList();

      if (mounted && cleaned.isNotEmpty) {
        // Apply smart shuffling to loaded songs
        final shuffledSongs =
            _applySmartShuffleToSection(cleaned, recentlyPlayed);
        // Deduplicate against all previously loaded sections
        final dedupedSongs = _globalDedup(shuffledSongs);

        if (dedupedSongs.isNotEmpty) {
          setState(() {
            _loaded.add(_LoadedSection(
              title: '${def.emoji} ${def.title}',
              songs: dedupedSongs.take(20).toList(),
              vertical: def.vertical,
            ));
          });
        }
      }
    } catch (_) {}

    if (forceIndex == null && mounted) setState(() => _isLoadingMore = false);
  }

  /// Apply smart shuffling to a section based on user preferences
  List<Song> _applySmartShuffleToSection(
      List<Song> songs, List<Song> recentlyPlayed) {
    if (songs.isEmpty) return songs;

    final shuffled = List<Song>.from(songs);
    final random = Random();

    // Extract preferred artists from recent plays
    final preferredArtists = <String>{};
    for (final song in recentlyPlayed.take(5)) {
      preferredArtists.add(song.artist.toLowerCase());
    }

    // Sort with preference bias
    shuffled.sort((a, b) {
      final aPreferred = preferredArtists.contains(a.artist.toLowerCase());
      final bPreferred = preferredArtists.contains(b.artist.toLowerCase());

      if (aPreferred && !bPreferred) return -1;
      if (!aPreferred && bPreferred) return 1;

      // Add randomness for variety
      return random.nextBool() ? -1 : 1;
    });

    return shuffled;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeModeProvider);
    ref.watch(themeColorProvider);
    final trendingMusic = ref.watch(trendingMusicProvider);
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);
    final hitsHindi = _wave2 ? ref.watch(hitsHindiProvider) : null;
    final recommendations =
        _wave2 ? ref.watch(personalizedFromHistoryProvider) : null;
    final todaysBiggest = _wave3 ? ref.watch(todaysBiggestHitsProvider) : null;
    final newReleases = _wave3 ? ref.watch(newReleasesProvider) : null;
    final featuredPlaylists =
        _wave3 ? ref.watch(featuredPlaylistsProvider) : null;

    return Scaffold(
      backgroundColor: AppColors.deepSpaceBlack,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.neonPink,
          backgroundColor: AppColors.deepSpaceBlackLight,
          onRefresh: _onRefresh,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Header ────────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildHeader()),

              // ── Quick grid (recently played) ──────────────────────────
              if (recentlyPlayed.isNotEmpty)
                SliverToBoxAdapter(
                  child:
                      RepaintBoundary(child: _buildQuickGrid(recentlyPlayed)),
                ),

              // ── Wave 1: Trending ──────────────────────────────────────
              SliverToBoxAdapter(
                child: RepaintBoundary(
                  child: _buildHorizSection('🔥 Trending Now', trendingMusic),
                ),
              ),

              // ── Wave 2: Hindi Hits ────────────────────────────────────
              if (_wave2 && hitsHindi != null)
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: _buildHorizSection('🎵 Hot Hits Hindi', hitsHindi),
                  ),
                ),

              // ── Wave 2: Made for You (Spotify recommendations) ───────
              if (_wave2 && recommendations != null)
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child:
                        _buildHorizSection('🎯 Made for You', recommendations),
                  ),
                ),

              // ── Wave 3: Today's Biggest Hits ─────────────────────────
              if (_wave3 && todaysBiggest != null)
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: _buildHorizSection(
                        "🏆 Today's Biggest Hits", todaysBiggest),
                  ),
                ),

              // ── Wave 3: New Releases ──────────────────────────────────
              if (_wave3 && newReleases != null)
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: _buildHorizSection('🆕 New Releases', newReleases),
                  ),
                ),

              // ── Wave 3: Spotify Featured Playlists ───────────────────
              if (_wave3 && featuredPlaylists != null)
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: _buildFeaturedPlaylists(featuredPlaylists),
                  ),
                ),

              // ── Infinite dynamic sections ─────────────────────────────
              ..._loaded.map((sec) => SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: sec.vertical
                          ? _buildVertSection(sec.title, sec.songs)
                          : _buildHorizSongs(sec.title, sec.songs),
                    ),
                  )),

              // ── Infinite loading indicator ────────────────────────────
              SliverToBoxAdapter(
                child: _isLoadingMore
                    ? Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              color: AppColors.neonPink,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(height: 110),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Pull to refresh ────────────────────────────────────────────────────────

  Future<void> _onRefresh() async {
    // Refresh app_config so creatorName and settings are always current
    _fetchAppConfig();

    // Smart refresh with enhanced shuffling
    invalidateAllMusicProviders(ref);

    setState(() {
      _loaded.clear();
      _nextIdx = 0;
      _globalSeenIds.clear();
      _globalSeenTitles.clear();
      // Enhanced queue shuffling with user preference consideration
      _queue.shuffle(Random());
      _wave2 = false;
      _wave3 = false;
    });

    // Load fresh sections with staggered timing for smooth experience
    _loadNextSection(0);
    _loadNextSection(1);
    _loadNextSection(2);
    _nextIdx = 3;

    // Staggered wave activation for better UX
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _wave2 = true);

    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() => _wave3 = true);

    // Show refresh feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.refresh, color: AppColors.textPrimary, size: 16),
              SizedBox(width: 8),
              Text('Fresh music loaded based on your taste!'),
            ],
          ),
          backgroundColor: AppColors.neonPink,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void _onLogoTap() async {
    final now = DateTime.now();
    if (_lastLogoTapTime == null ||
        now.difference(_lastLogoTapTime!) > const Duration(seconds: 2)) {
      _logoTapCount = 1;
    } else {
      _logoTapCount++;
    }
    _lastLogoTapTime = now;

    if (_logoTapCount >= 7) {
      _logoTapCount = 0;
      final prefs = await SharedPreferences.getInstance();
      final lastAccessMs = prefs.getInt('last_console_access_timestamp') ?? 0;
      final lastAccess = DateTime.fromMillisecondsSinceEpoch(lastAccessMs);
      
      if (lastAccessMs > 0 && now.difference(lastAccess).inHours < 24) {
        _openSecretConsoleDirectly();
      } else {
        _showSecretPasswordDialog();
      }
    }
  }

  void _openSecretConsoleDirectly() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_console_access_timestamp', DateTime.now().millisecondsSinceEpoch);

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SecretConsoleScreen()),
      ).then((value) {
        if (value == true && mounted) {
          setState(() {}); // Refresh home screen to apply overrides immediately
        }
      });
    }
  }

  void _showSecretPasswordDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.deepSpaceBlackLight,
        title: const Text('Developer Console',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter Developer Passcode:',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Passcode',
                hintStyle:
                    TextStyle(color: AppColors.textSecondary.withOpacity(0.4)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.neonPink)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final passwordEntered = controller.text.trim();
              // Validate directly against Firestore — no hardcoded fallback
              final isValid = await SecurityEngine()
                  .validateSecretConsolePasscode(passwordEntered);

              if (isValid) {
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('last_console_access_timestamp',
                      DateTime.now().millisecondsSinceEpoch);

                  if (mounted) {
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                          builder: (context) => const SecretConsoleScreen()),
                    ).then((value) {
                      if (value == true && mounted) {
                        setState(() {});
                      }
                    });
                  }
                }
              } else {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text('Incorrect Passcode!'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: Text('Enter',
                style: TextStyle(
                    color: AppColors.neonPink, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Builder(
        builder: (context) {
          final localOverrideEnabled =
              _prefs?.getBool('local_override_enabled') ?? false;

          // Resolve display name:
          // Local override → app_config creatorName → user_name prefs → fallback
          final savedDisplayName =
              _prefs?.getString('user_name')?.trim() ?? '';
          final firestoreCreatorName =
              _appConfig['creatorName']?.toString().trim() ?? '';
          final overrideName =
              _prefs?.getString('local_override_creator_name')?.trim() ?? '';

          String creatorName;
          if (localOverrideEnabled && overrideName.isNotEmpty) {
            creatorName = overrideName;
          } else if (firestoreCreatorName.isNotEmpty) {
            creatorName = firestoreCreatorName;
          } else if (savedDisplayName.isNotEmpty) {
            creatorName = savedDisplayName;
          } else {
            creatorName = 'Unknown User';
          }

          // Resolve visibility flags from app_config, with local override
          final showLinkedin = localOverrideEnabled
              ? (_prefs?.getBool('local_override_show_linkedin') ?? true)
              : ((_appConfig['showLinkedin'] ?? true) as bool);

          final showContact = localOverrideEnabled
              ? (_prefs?.getBool('local_override_show_contact') ?? true)
              : ((_appConfig['showContact'] ?? true) as bool);

          final linkedinUrl = localOverrideEnabled
              ? (_prefs?.getString('local_override_linkedin_url')
                    ?.isNotEmpty == true
                  ? _prefs!.getString('local_override_linkedin_url')!
                  : _appConfig['linkedinUrl']?.toString() ??
                      'https://www.linkedin.com/in/sandipan-bhunia/')
              : (_appConfig['linkedinUrl']?.toString() ??
                  'https://www.linkedin.com/in/sandipan-bhunia/');

          final contactNumber = localOverrideEnabled
              ? (_prefs?.getString('local_override_contact_number')
                    ?.isNotEmpty == true
                  ? _prefs!.getString('local_override_contact_number')!
                  : _appConfig['contactNumber']?.toString() ?? '8972966158')
              : (_appConfig['contactNumber']?.toString() ?? '8972966158');

          final items = <Widget>[];

          // YouTube Import Link Button
          items.add(
            GestureDetector(
              onTap: () => ImportLinkModal.show(context),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.link_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          );
          items.add(const SizedBox(width: 8));

          // LinkedIn
          if (showLinkedin) {
            items.add(
              GestureDetector(
                onTap: () => _launchUrl(linkedinUrl),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A66C2),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0A66C2).withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'in',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          if (showLinkedin && showContact) {
            items.add(const SizedBox(width: 8));
          }

          // Contact (SMS)
          if (showContact) {
            items.add(
              GestureDetector(
                onTap: () => _launchUrl('sms:$contactNumber'),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF25D366).withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child:
                        Icon(Icons.chat_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
            );
          }

          if (showLinkedin || showContact) {
            items.add(const SizedBox(width: 8));
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── App icon ──────────────────────────────────────────────────
                GestureDetector(
                  onTap: _onLogoTap,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [AppColors.neonPink, AppColors.neonCoral]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.headphones_rounded,
                        color: AppColors.textPrimary, size: 22),
                  ),
                ),
                const SizedBox(width: 12),

                // ── App name + taglines ───────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Aura Player',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                      Text('Vibe with your music',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [AppColors.neonPink, AppColors.neonCoral],
                        ).createShader(bounds),
                        child: Text(
                          'Made by $creatorName ✦',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3),
                        ),
                      ),
                    ],
                  ),
                ),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: items,
                ),
              ],
            ),
          );
        },
      );

  Future<void> _launchUrl(String url) async {
    try {
      await _openUrl(Uri.parse(url));
    } catch (_) {}
  }

  Widget _buildQuickGrid(List<Song> songs) {
    final shown = songs.take(6).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 3.5,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final song = shown[i];
          final playing =
              ref.watch(currentSongProvider).valueOrNull?.id == song.id;
          return Material(
            color: playing
                ? AppColors.neonPink.withValues(alpha: 0.18)
                : AppColors.deepSpaceBlackLight,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                ref.read(audioServiceProvider).loadQueue(
                      songs,
                      startIndex: i,
                      context: PlaybackContext
                          .radio, // home sections → autoplay after queue ends
                    );
                ref.read(recentlyPlayedProvider.notifier).add(song);
              },
              child: Row(children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      bottomLeft: Radius.circular(6)),
                  child: _img(song.albumArt, 52, 52),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(song.title,
                      style: TextStyle(
                          color: playing
                              ? AppColors.neonPink
                              : AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                if (playing)
                  Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.equalizer_rounded,
                        color: AppColors.neonPink, size: 14),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // Provider-backed horizontal section
  Widget _buildHorizSection(String title, AsyncValue<List<Song>> data) =>
      data.when(
        skipLoadingOnRefresh: true,
        data: (songs) => songs.isEmpty
            ? const SizedBox.shrink()
            : _buildHorizSongs(title, songs),
        loading: () => _loadingRow(title),
        error: (_, __) => const SizedBox.shrink(),
      );

  // Data-backed horizontal section (infinite sections)
  Widget _buildHorizSongs(String title, List<Song> songs) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secTitle(title),
          SizedBox(
            height: 188,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final song = songs[i];
                final playing =
                    ref.watch(currentSongProvider).valueOrNull?.id == song.id;
                return GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlaylistScreen(
                          playlistTitle: title,
                          coverUrl: song.albumArt,
                          songs: songs,
                        ),
                      )),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: SizedBox(
                      width: 128,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _img(song.albumArt, 128, 128),
                            ),
                            if (playing)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.equalizer_rounded,
                                      color: AppColors.neonPink, size: 34),
                                ),
                              ),
                          ]),
                          const SizedBox(height: 6),
                          Text(song.title,
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(song.artist,
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      );

  // Vertical list section (Lo-fi / Bengali / Bhojpuri etc.)
  Widget _buildVertSection(String title, List<Song> songs) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secTitle(title),
          ...songs.take(5).map((song) {
            final playing =
                ref.watch(currentSongProvider).valueOrNull?.id == song.id;
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: _img(song.albumArt, 50, 50),
              ),
              title: Text(song.title,
                  style: TextStyle(
                      color:
                          playing ? AppColors.neonPink : AppColors.textPrimary,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(song.artist,
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              trailing: playing
                  ? Icon(Icons.equalizer_rounded, color: AppColors.neonPink)
                  : IconButton(
                      icon:
                          Icon(Icons.more_vert, color: AppColors.textSecondary),
                      onPressed: () =>
                          PlaylistDialogs.showSongOptions(context, ref, song),
                    ),
              onTap: () {
                ref.read(audioServiceProvider).loadQueue(
                      songs,
                      startIndex: songs.indexOf(song),
                      context: PlaybackContext.radio,
                    );
                ref.read(recentlyPlayedProvider.notifier).add(song);
              },
            );
          }),
          const SizedBox(height: 24),
        ],
      );

  // Spotify Featured Playlists section
  Widget _buildFeaturedPlaylists(AsyncValue<List<SpotifyPlaylist>> data) =>
      data.when(
        skipLoadingOnRefresh: true,
        data: (playlists) {
          if (playlists.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secTitle('🎵 Featured Playlists'),
              SizedBox(
                height: 188,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: playlists.length,
                  itemBuilder: (context, i) {
                    final playlist = playlists[i];
                    return GestureDetector(
                      onTap: () {
                        // Load playlist songs and navigate
                        ref
                            .read(playlistSongsProvider(playlist.id).future)
                            .then((songs) {
                          if (songs.isNotEmpty && context.mounted) {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PlaylistScreen(
                                    playlistTitle: playlist.name,
                                    coverUrl: playlist.imageUrl,
                                    songs: songs,
                                  ),
                                ));
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: SizedBox(
                          width: 128,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: _img(playlist.imageUrl, 128, 128),
                              ),
                              const SizedBox(height: 6),
                              Text(playlist.name,
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              if (playlist.description != null &&
                                  playlist.description!.isNotEmpty)
                                Text(playlist.description!,
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
        loading: () => _loadingRow('🎵 Featured Playlists'),
        error: (_, __) => const SizedBox.shrink(),
      );

  Widget _loadingRow(String title) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secTitle(title),
          SizedBox(
            height: 188,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: AppColors.neonPink, strokeWidth: 2),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      );

  Widget _secTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Text(title,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3)),
      );

  /// Network image with capped decode size to prevent GPU texture overflow.
  Widget _img(String? url, double w, double h) {
    if (url == null || url.isEmpty) {
      return Container(
        width: w,
        height: h,
        color: AppColors.deepSpaceBlackLight,
        child: Icon(Icons.music_note, color: AppColors.divider, size: w * 0.4),
      );
    }
    return Image.network(
      url,
      width: w,
      height: h,
      fit: BoxFit.cover,
      cacheWidth: (w * 1.5).toInt(),
      cacheHeight: (h * 1.5).toInt(),
      errorBuilder: (_, __, ___) => Container(
        width: w,
        height: h,
        color: AppColors.deepSpaceBlackLight,
        child: Icon(Icons.music_note, color: AppColors.divider, size: w * 0.4),
      ),
      loadingBuilder: (_, child, prog) => prog == null
          ? child
          : Container(
              width: w,
              height: h,
              color: AppColors.deepSpaceBlackLighter,
              child: Center(
                child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: AppColors.neonPink, strokeWidth: 1.5)),
              ),
            ),
    );
  }
}
