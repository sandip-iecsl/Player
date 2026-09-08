class DependencyContainer {
  static final DependencyContainer _instance = DependencyContainer._internal();
  factory DependencyContainer() => _instance;
  DependencyContainer._internal();

  final Map<Type, dynamic Function()> _factories = {};
  final Map<Type, dynamic> _singletons = {};
  final Map<Type, dynamic Function()> _lazyFactories = {};

  /// Registers a singleton instance directly.
  void registerSingleton<T>(T instance) {
    _singletons[T] = instance;
  }

  /// Registers a lazy singleton factory.
  void registerLazySingleton<T>(T Function() factory) {
    _lazyFactories[T] = factory;
  }

  /// Registers a factory that creates a new instance on every call.
  void registerFactory<T>(T Function() factory) {
    _factories[T] = factory;
  }

  /// Resolves the registered dependency.
  T get<T>() {
    // 1. Check existing singletons
    if (_singletons.containsKey(T)) {
      return _singletons[T] as T;
    }

    // 2. Check lazy singletons
    if (_lazyFactories.containsKey(T)) {
      final instance = _lazyFactories[T]!();
      _singletons[T] = instance;
      _lazyFactories.remove(T); // Promoted to singleton
      return instance as T;
    }

    // 3. Check factories
    if (_factories.containsKey(T)) {
      return _factories[T]!() as T;
    }

    throw Exception('Dependency of type $T is not registered in the container.');
  }

  /// Reset the container (useful during logout or application restart).
  void clear() {
    _factories.clear();
    _singletons.clear();
    _lazyFactories.clear();
  }
}
