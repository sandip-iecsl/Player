import '../../../core/cache/cache_eviction_engine.dart';
import '../../../core/kernel/i_engine.dart';

class CacheEngine implements IEngine {
  static final CacheEngine _instance = CacheEngine._internal();
  factory CacheEngine() => _instance;
  CacheEngine._internal();

  @override
  Future<void> initialize() async {
    await CacheEvictionEngine().initialize();
  }

  @override
  Future<void> start() async {}

  Future<void> pinChat(String roomId, bool pin) async {
    await CacheEvictionEngine().pinRoom(roomId, pin);
  }

  Future<void> archiveChat(String roomId, bool archive) async {
    await CacheEvictionEngine().archiveRoom(roomId, archive);
  }

  bool isPinned(String roomId) => CacheEvictionEngine().isPinned(roomId);
  bool isArchived(String roomId) => CacheEvictionEngine().isArchived(roomId);

  Future<void> evictCache() async {
    await CacheEvictionEngine().runEviction();
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
