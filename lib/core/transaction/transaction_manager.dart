import 'dart:async';
import 'package:flutter/widgets.dart';
import '../kernel/i_engine.dart';
import '../shared/error/error_manager.dart';

class TransactionStep {
  final String id;
  final FutureOr<void> Function() execute;
  final FutureOr<void> Function() rollback;

  TransactionStep({
    required this.id,
    required this.execute,
    required this.rollback,
  });
}

class TransactionManager implements IEngine {
  static final TransactionManager _instance = TransactionManager._internal();
  factory TransactionManager() => _instance;
  TransactionManager._internal();

  final List<TransactionStep> _stepsJournal = [];
  final List<TransactionStep> _completedSteps = [];
  bool _inTransaction = false;

  @override
  Future<void> initialize() async {
    debugPrint('[TransactionManager] 🗃️ Client-side transaction tracking engine initialized.');
  }

  @override
  Future<void> start() async {}

  /// Starts a client database transaction block.
  void beginTransaction() {
    if (_inTransaction) {
      throw Exception('TransactionManager: A transaction is already in progress.');
    }
    _inTransaction = true;
    _stepsJournal.clear();
    _completedSteps.clear();
    debugPrint('[TransactionManager] 🗃️ Transaction block started.');
  }

  /// Adds a step to the transaction.
  void addStep(TransactionStep step) {
    if (!_inTransaction) {
      throw Exception('TransactionManager: No active transaction.');
    }
    _stepsJournal.add(step);
  }

  /// Executes all registered steps in sequence, rolling back completed steps if any step fails.
  Future<bool> commit() async {
    if (!_inTransaction) {
      throw Exception('TransactionManager: No transaction to commit.');
    }

    debugPrint('[TransactionManager] 🗃️ Committing transaction containing ${_stepsJournal.length} operations...');

    for (final step in _stepsJournal) {
      try {
        await step.execute();
        _completedSteps.add(step);
      } catch (e, stack) {
        ErrorManager().captureError(e, stack, context: 'Transaction.commit.${step.id}');
        debugPrint('[TransactionManager] ⚠️ Step ${step.id} failed execution. Commencing rollback...');
        await rollback();
        return false;
      }
    }

    _inTransaction = false;
    _stepsJournal.clear();
    _completedSteps.clear();
    debugPrint('[TransactionManager] 🎉 Transaction committed successfully.');
    return true;
  }

  /// Reverts all completed operations within the current block.
  Future<void> rollback() async {
    debugPrint('[TransactionManager] 🗃️ Rolling back ${_completedSteps.length} completed operations...');
    
    // Rollback in reverse execution order (LIFO)
    for (final step in _completedSteps.reversed) {
      try {
        await step.rollback();
        debugPrint('[TransactionManager] 🗃️ Reverted step: ${step.id}');
      } catch (e) {
        debugPrint('[TransactionManager] ❌ Rollback step ${step.id} failed: $e');
      }
    }

    _inTransaction = false;
    _stepsJournal.clear();
    _completedSteps.clear();
    debugPrint('[TransactionManager] 🗃️ Rollback completed.');
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    if (_inTransaction) {
      await rollback();
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
