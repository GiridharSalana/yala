// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider exposing the singleton [RouterScopedOperationQueue].
final operationQueueProvider = Provider<RouterScopedOperationQueue>(
  (ref) => RouterScopedOperationQueue.instance,
);

/// A pending lock request in a domain or exclusive queue.
class _PendingOperation {
  final String domain;
  final Completer<void> completer = Completer<void>();
  bool isDisposed = false;

  _PendingOperation(this.domain);
}

/// Internal lock state for a single router.
class _RouterLockState {
  /// Number of active exclusive operations (0 or 1).
  int activeExclusive = 0;

  /// Count of exclusive operations waiting to acquire lock.
  /// When > 0, newly arriving normal operations must wait to prevent starvation.
  int waitingExclusiveCount = 0;

  /// FIFO queue of waiting exclusive operations.
  final List<_PendingOperation> exclusiveQueue = [];

  /// Map of domain -> active count (0 or 1).
  final Map<String, int> activeDomains = {};

  /// Map of domain -> FIFO queue of waiting operations.
  final Map<String, List<_PendingOperation>> domainQueues = {};

  /// Whether this router has no active and no pending operations.
  bool get isIdle =>
      activeExclusive == 0 &&
      waitingExclusiveCount == 0 &&
      exclusiveQueue.isEmpty &&
      activeDomains.isEmpty &&
      domainQueues.values.every((q) => q.isEmpty);

  /// Checks if a domain is currently busy or blocked by an active/pending exclusive operation.
  bool isBusy(String domain) {
    if (activeExclusive > 0 || waitingExclusiveCount > 0) return true;
    if (domain == '*') {
      return activeDomains.isNotEmpty;
    }
    return (activeDomains[domain] ?? 0) > 0;
  }
}

/// Router-scoped concurrency and operation serialization manager.
///
/// Features:
/// 1. Router isolation: Operations on different routers execute concurrently.
/// 2. Domain isolation: Operations on the same router for different domains execute concurrently.
/// 3. Same domain serialization: Operations on the same router for the same domain execute sequentially.
/// 4. Router-exclusive locking: Operations with domain `'*'` wait for all active domains to complete,
///    block subsequent normal operations from starting (preventing starvation), and execute exclusively.
/// 5. Timeout safety: Timed-out requests are removed cleanly without leaving stale locks.
/// 6. Error safety: Lock release is guaranteed via `finally` blocks.
/// 7. Non-intrusive polling: [isBusy] allows background polling to skip busy domains without throwing.
class RouterScopedOperationQueue {
  RouterScopedOperationQueue._();

  static final RouterScopedOperationQueue instance =
      RouterScopedOperationQueue._();

  final Map<String, _RouterLockState> _routerStates = {};

  _RouterLockState _getState(String routerId) {
    return _routerStates.putIfAbsent(routerId, () => _RouterLockState());
  }

  void _cleanupIfIdle(String routerId) {
    final state = _routerStates[routerId];
    if (state != null && state.isIdle) {
      _routerStates.remove(routerId);
    }
  }

  /// Checks if a router or domain is currently busy.
  ///
  /// Useful for background polling loops to skip conflicting polls gracefully.
  bool isBusy(String routerId, String domain) {
    final state = _routerStates[routerId];
    if (state == null) return false;
    return state.isBusy(domain);
  }

  /// Runs [action] exclusively within [domain] for the router identified by [routerId].
  ///
  /// If [domain] is `'*'`, the operation acquires a router-exclusive lock.
  /// [timeout] defines the maximum duration to wait to acquire the lock. Default is 15 seconds.
  Future<T> runLocked<T>({
    required String routerId,
    required String domain,
    required Future<T> Function() action,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final activeLockKey = 'operation_queue_lock_$routerId';
    final heldDomain = Zone.current[Symbol(activeLockKey)] as String?;
    if (heldDomain != null && (heldDomain == domain || heldDomain == '*')) {
      return await action();
    }

    await _acquire(routerId, domain, timeout);
    try {
      return await runZoned(
        action,
        zoneValues: {Symbol(activeLockKey): domain},
      );
    } finally {
      _release(routerId, domain);
    }
  }

  Future<void> _acquire(
    String routerId,
    String domain,
    Duration timeout,
  ) async {
    final state = _getState(routerId);

    if (domain == '*') {
      // Exclusive operation
      if (state.activeExclusive == 0 &&
          state.activeDomains.isEmpty &&
          state.waitingExclusiveCount == 0) {
        state.activeExclusive = 1;
        return;
      }

      state.waitingExclusiveCount++;
      final op = _PendingOperation('*');
      state.exclusiveQueue.add(op);

      try {
        await op.completer.future.timeout(timeout);
      } on TimeoutException {
        op.isDisposed = true;
        state.exclusiveQueue.remove(op);
        state.waitingExclusiveCount--;
        if (op.completer.isCompleted) {
          // Raced with being granted right as timeout fired
          _release(routerId, '*');
        } else {
          _pumpQueues(state);
          _cleanupIfIdle(routerId);
        }
        rethrow;
      }
    } else {
      // Normal domain operation
      if (state.activeExclusive == 0 &&
          state.waitingExclusiveCount == 0 &&
          (state.activeDomains[domain] ?? 0) == 0) {
        state.activeDomains[domain] = 1;
        return;
      }

      final op = _PendingOperation(domain);
      state.domainQueues.putIfAbsent(domain, () => []).add(op);

      try {
        await op.completer.future.timeout(timeout);
      } on TimeoutException {
        op.isDisposed = true;
        state.domainQueues[domain]?.remove(op);
        if (op.completer.isCompleted) {
          // Raced with being granted right as timeout fired
          _release(routerId, domain);
        } else {
          _pumpQueues(state);
          _cleanupIfIdle(routerId);
        }
        rethrow;
      }
    }
  }

  void _release(String routerId, String domain) {
    final state = _routerStates[routerId];
    if (state == null) return;

    if (domain == '*') {
      state.activeExclusive = 0;
    } else {
      state.activeDomains.remove(domain);
    }

    _pumpQueues(state);
    _cleanupIfIdle(routerId);
  }

  void _pumpQueues(_RouterLockState state) {
    if (state.activeExclusive > 0) {
      // Exclusive is running; nothing else can start.
      return;
    }

    if (state.waitingExclusiveCount > 0) {
      // An exclusive operation is waiting.
      if (state.activeDomains.isEmpty) {
        // All active domains have drained: grant the next exclusive operation.
        while (state.exclusiveQueue.isNotEmpty) {
          final op = state.exclusiveQueue.removeAt(0);
          state.waitingExclusiveCount--;
          if (!op.isDisposed && !op.completer.isCompleted) {
            state.activeExclusive = 1;
            op.completer.complete();
            return;
          }
        }
      }
      // If activeDomains is not empty, wait for them to drain before starting exclusive.
      // Do NOT start any new domain operations while an exclusive is waiting (prevents starvation).
      return;
    }

    // No exclusive active and none waiting: start waiting operations across idle domains.
    for (final domain in state.domainQueues.keys.toList()) {
      if ((state.activeDomains[domain] ?? 0) == 0) {
        final queue = state.domainQueues[domain];
        if (queue != null) {
          while (queue.isNotEmpty) {
            final op = queue.removeAt(0);
            if (!op.isDisposed && !op.completer.isCompleted) {
              state.activeDomains[domain] = 1;
              op.completer.complete();
              break;
            }
          }
        }
      }
    }
  }
}
