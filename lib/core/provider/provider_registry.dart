import 'package:flutter/widgets.dart';
import '../kernel/i_engine.dart';

abstract class IExtensibleProvider {
  Future<void> initialize();
  Future<bool> healthCheck();
  int priority();
  bool supports(String feature);
  Future<void> shutdown();
}

class ProviderRegistry implements IEngine {
  static final ProviderRegistry _instance = ProviderRegistry._internal();
  factory ProviderRegistry() => _instance;
  ProviderRegistry._internal();

  final List<IExtensibleProvider> _providers = [];

  @override
  Future<void> initialize() async {
    debugPrint('[ProviderRegistry] 🔌 Extensible provider directory initialized.');
  }

  @override
  Future<void> start() async {}

  /// Register an extensible client adapter.
  void registerProvider(IExtensibleProvider provider) {
    _providers.add(provider);
    provider.initialize();
    debugPrint('[ProviderRegistry] 🔌 Registered provider of type ${provider.runtimeType} (Priority: ${provider.priority()})');
  }

  /// Locate all registered adapters matching support category.
  List<T> getProvidersFor<T>(String feature) {
    return _providers
        .where((p) => p.supports(feature) && p is T)
        .cast<T>()
        .toList();
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    for (final provider in _providers) {
      await provider.shutdown();
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    _providers.clear();
  }
}
