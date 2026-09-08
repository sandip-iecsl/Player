import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:aura_player/core/search/search_tier.dart';
import 'package:aura_player/core/search/search_engine_provider.dart';
import 'package:aura_player/core/search/search_debouncer.dart';
import 'package:aura_player/core/search/failover_search_coordinator.dart';
import 'package:aura_player/data/models/song_model.dart';

class MockFailingProvider implements ISearchEngineProvider {
  @override
  final String providerName;
  @override
  final SearchTier tier;
  final Duration delay;
  final bool shouldThrow;

  MockFailingProvider({
    required this.providerName,
    required this.tier,
    this.delay = Duration.zero,
    this.shouldThrow = true,
  });

  @override
  Future<List<SongModel>> search(String query) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    if (shouldThrow) {
      throw Exception('Simulated 429 Rate Limit / Network Outage on $providerName');
    }
    return [];
  }

  @override
  Future<bool> isHealthy() async => false;
}

class MockSuccessProvider implements ISearchEngineProvider {
  @override
  final String providerName;
  @override
  final SearchTier tier;
  final List<SongModel> mockSongs;

  MockSuccessProvider({
    required this.providerName,
    required this.tier,
    required this.mockSongs,
  });

  @override
  Future<List<SongModel>> search(String query) async {
    return mockSongs;
  }

  @override
  Future<bool> isHealthy() async => true;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_search_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    try {
      await Hive.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Zero-Cost Failover Search Architecture Tests', () {
    test('Debouncer cancels rapid keystrokes and fires single callback', () async {
      final debouncer = SearchDebouncer(delay: const Duration(milliseconds: 100));
      int callCount = 0;

      debouncer.run(() => callCount++);
      debouncer.run(() => callCount++);
      debouncer.run(() => callCount++);

      expect(callCount, equals(0));
      await Future.delayed(const Duration(milliseconds: 150));
      expect(callCount, equals(1));
    });

    test('Failover coordinator seamlessly transitions from Tier 1 -> Tier 2 -> Tier 3 on failure', () async {
      final mockSong = SongModel(
        id: 'offline_101',
        title: 'Starboy',
        artist: 'The Weeknd',
        duration: const Duration(seconds: 230),
      );

      final tier1 = MockFailingProvider(
        providerName: 'MongoDB Atlas (Primary)',
        tier: SearchTier.tier1MongoAtlas,
      );

      final tier2 = MockFailingProvider(
        providerName: 'Algolia (Backup)',
        tier: SearchTier.tier2Algolia,
      );

      final tier3 = MockSuccessProvider(
        providerName: 'Local CPU Fuzzy Engine (Tier 3)',
        tier: SearchTier.tier3LocalFailsafe,
        mockSongs: [mockSong],
      );

      final coordinator = FailoverSearchCoordinator(
        providers: [tier1, tier2, tier3],
        perProviderTimeout: const Duration(seconds: 1),
      );

      final result = await coordinator.executeSearch('Starboy', bypassCache: true);

      expect(result.songs.length, equals(1));
      expect(result.songs.first.title, equals('Starboy'));
      expect(result.tier, equals(SearchTier.tier3LocalFailsafe));
      expect(result.providerName, equals('Local CPU Fuzzy Engine (Tier 3)'));

      coordinator.dispose();
    });

    test('Failover coordinator handles provider timeout and switches to next tier', () async {
      final mockSong = SongModel(
        id: 'algolia_202',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        duration: const Duration(seconds: 200),
      );

      // Tier 1 hangs longer than timeout limit
      final tier1Hanging = MockFailingProvider(
        providerName: 'MongoDB Atlas (Hanging)',
        tier: SearchTier.tier1MongoAtlas,
        delay: const Duration(milliseconds: 300),
        shouldThrow: false,
      );

      // Tier 2 resolves quickly
      final tier2Fast = MockSuccessProvider(
        providerName: 'Algolia (Tier 2)',
        tier: SearchTier.tier2Algolia,
        mockSongs: [mockSong],
      );

      final coordinator = FailoverSearchCoordinator(
        providers: [tier1Hanging, tier2Fast],
        perProviderTimeout: const Duration(milliseconds: 100),
      );

      final result = await coordinator.executeSearch('Blinding Lights', bypassCache: true);

      expect(result.songs.length, equals(1));
      expect(result.songs.first.id, equals('algolia_202'));
      expect(result.tier, equals(SearchTier.tier2Algolia));

      await Future.delayed(const Duration(milliseconds: 100));
      coordinator.dispose();
    });
  });
}
