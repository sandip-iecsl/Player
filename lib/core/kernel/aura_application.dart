import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../di/dependency_container.dart';
import 'engine_coordinator.dart';
import 'lifecycle_manager.dart';
import 'configuration_manager.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/repositories/admin_repository.dart';
import '../sync/adaptive_sync_engine.dart';
import '../cache/cache_eviction_engine.dart';
import '../shared/scheduler/scheduler_engine.dart';
import '../shared/error/error_manager.dart';
import '../shared/recovery/recovery_manager.dart';
import '../shared/resource/resource_manager.dart';
import '../shared/metrics/metrics_engine.dart';
import '../../features/chat/engines/presence_engine.dart';
import '../../features/chat/engines/notification_engine.dart';
import '../../features/chat/engines/cache_engine.dart';
import '../migration/migration_engine.dart';
import '../task/task_manager.dart';
import '../security/security_policy_engine.dart';
import '../capability/device_capability_engine.dart';
import '../config/configuration_registry.dart';
import '../provider/provider_registry.dart';
import '../transaction/transaction_manager.dart';
import '../permission/permission_engine.dart';

class AuraApplication {
  static final AuraApplication _instance = AuraApplication._internal();
  factory AuraApplication() => _instance;
  AuraApplication._internal();

  bool _isBootstrapped = false;
  String? _authenticatedUid;

  String get authenticatedUid {
    if (_authenticatedUid == null) {
      throw Exception('AuraApplication: Authenticated UID is not ready. Call bootstrap first.');
    }
    return _authenticatedUid!;
  }

  /// Central bootstrapping sequence for the application.
  Future<void> bootstrap() async {
    if (_isBootstrapped) return;

    debugPrint('[AuraApplication] 🚀 Starting bootstrapping sequence...');

    // 1. Initialize configurations
    await ConfigurationManager().init();

    // 2. Initialize Firebase Anonymous Auth & block until UID is ready
    final auth = FirebaseAuth.instance;
    User? currentUser = auth.currentUser;
    
    if (currentUser == null) {
      debugPrint('[AuraApplication] 🔑 Authenticating anonymously...');
      try {
        final credential = await auth.signInAnonymously();
        currentUser = credential.user;
      } catch (e) {
        debugPrint('[AuraApplication] ❌ Anonymous Auth failed: $e');
        rethrow;
      }
    }

    if (currentUser == null) {
      throw Exception('AuraApplication: Anonymous authentication returned null user.');
    }

    _authenticatedUid = currentUser.uid;
    debugPrint('[AuraApplication] 🔑 Authenticated anonymously under UID: $_authenticatedUid');

    // 3. Register Dependency bindings
    _registerDependencies();

    // 4. Initialize Coordinator Engines
    await EngineCoordinator().initialize();

    // 5. Start Core Engines
    await EngineCoordinator().start();

    // 6. Start Lifecycle Monitoring
    LifecycleManager().startListening();

    _isBootstrapped = true;
    debugPrint('[AuraApplication] 🎉 Bootstrapping completed successfully.');
  }

  void _registerDependencies() {
    final di = DependencyContainer();
    // Clear previous registrations
    di.clear();

    // Register kernel coordinators
    di.registerSingleton<EngineCoordinator>(EngineCoordinator());
    di.registerSingleton<ConfigurationManager>(ConfigurationManager());

    final coordinator = EngineCoordinator();

    // Phase 1: Core engines
    coordinator.registerEngine(SchedulerEngine(), 1);
    coordinator.registerEngine(ErrorManager(), 1);
    coordinator.registerEngine(RecoveryManager(), 1);
    coordinator.registerEngine(ResourceManager(), 1);
    coordinator.registerEngine(MigrationEngine(), 1);
    coordinator.registerEngine(TaskManager(), 1);

    // Phase 2: System engines & Repositories
    coordinator.registerEngine(MetricsEngine(), 2);
    coordinator.registerEngine(AdaptiveSyncEngine(), 2);
    coordinator.registerEngine(CacheEvictionEngine(), 2);
    coordinator.registerEngine(ChatRepository(), 2);
    coordinator.registerEngine(AdminRepository(), 2);
    coordinator.registerEngine(SecurityPolicyEngine(), 2);
    coordinator.registerEngine(DeviceCapabilityEngine(), 2);
    coordinator.registerEngine(ConfigurationRegistry(), 2);
    coordinator.registerEngine(ProviderRegistry(), 2);
    coordinator.registerEngine(TransactionManager(), 2);
    coordinator.registerEngine(PermissionEngine(), 2);

    // Phase 4: Feature engines
    coordinator.registerEngine(CacheEngine(), 4);
    coordinator.registerEngine(PresenceEngine(), 4);
    coordinator.registerEngine(NotificationEngine(), 4);
  }

  /// Clean shutdown of engines and container registry.
  Future<void> shutdown() async {
    if (!_isBootstrapped) return;
    
    debugPrint('[AuraApplication] 🛑 Starting clean shutdown sequence...');
    LifecycleManager().stopListening();
    await EngineCoordinator().dispose();
    DependencyContainer().clear();
    _authenticatedUid = null;
    _isBootstrapped = false;
    debugPrint('[AuraApplication] 🛑 Shutdown sequence complete.');
  }

  /// Triggers a hard application reload/restart.
  Future<void> restart() async {
    await shutdown();
    await bootstrap();
  }
}
