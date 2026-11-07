import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sync/sync_service.dart';
import '../data/sync/sync_transport.dart';
import '../design_system/components.dart';

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.localOnly,
    this.pending = 0,
    this.lastSync,
    this.error,
    this.failures = 0,
  });
  final SyncPhase phase;
  final int pending;
  final DateTime? lastSync;
  final String? error;
  final int failures;
  SyncStatus copyWith({
    SyncPhase? phase,
    int? pending,
    DateTime? lastSync,
    String? error,
    int? failures,
    bool clearError = false,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    pending: pending ?? this.pending,
    lastSync: lastSync ?? this.lastSync,
    error: clearError ? null : (error ?? this.error),
    failures: failures ?? this.failures,
  );
}

/// Drives [SyncService] and exposes status for the UI. `service == null` means local-only.
class SyncController extends Notifier<SyncStatus> {
  SyncController(
    this.service, {
    this.interval = const Duration(seconds: 60),
    Random? jitter,
    this.isSignedIn,
    this.accountConflict,
  }) : _random = jitter ?? Random();
  final SyncService? service;

  /// Cloud sync only runs for a signed-in user. Null = always allowed (tests / no gating).
  final bool Function()? isSignedIn;

  /// Returns a message when this device's data belongs to a different account (sync must not mix them).
  final Future<String?> Function()? accountConflict;
  final Duration interval;
  final Random _random;
  Timer? _timer;

  @override
  SyncStatus build() {
    ref.onDispose(() => _timer?.cancel());
    if (service == null) return const SyncStatus(phase: SyncPhase.localOnly);
    return const SyncStatus(phase: SyncPhase.synced);
  }

  /// Start periodic sync (call after sign-in). Also call on app resume / connectivity regained.
  void start() {
    if (service == null) return;
    unawaited(syncNow());
  }

  Future<void> syncNow() async {
    final s = service;
    if (s == null) return;
    _timer?.cancel();
    if (isSignedIn != null && !isSignedIn!()) {
      state = SyncStatus(
        phase: SyncPhase.localOnly,
        pending: await s.pendingCount(),
        lastSync: await s.lastSuccessfulSync(),
      );
      return;
    }
    final conflict = await accountConflict?.call();
    if (conflict != null) {
      state = SyncStatus(
        phase: SyncPhase.attention,
        pending: await s.pendingCount(),
        error: conflict,
      );
      return;
    }
    state = state.copyWith(
      phase: SyncPhase.syncing,
      pending: await s.pendingCount(),
    );
    try {
      await s.sync();
      state = SyncStatus(
        phase: SyncPhase.synced,
        pending: await s.pendingCount(),
        lastSync: await s.lastSuccessfulSync(),
      );
      _schedule(interval);
    } on SyncTransportException catch (e) {
      final failures = state.failures + 1;
      state = state.copyWith(
        phase: e.retryable ? SyncPhase.offline : SyncPhase.attention,
        pending: await s.pendingCount(),
        error: e.message,
        failures: failures,
      );
      if (e.retryable) {
        final b = backoffFor(failures - 1);
        _schedule(
          b +
              Duration(
                milliseconds: _random.nextInt(b.inMilliseconds ~/ 4 + 1),
              ),
        ); // jitter
      }
    }
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, () => unawaited(syncNow()));
  }
}
