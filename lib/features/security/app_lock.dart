import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

abstract interface class Authenticator {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}

/// Windows Hello, Touch ID / Face ID, Android biometrics, with device credential fallback.
class LocalAuthAuthenticator implements Authenticator {
  LocalAuthAuthenticator([LocalAuthentication? a]) : _a = a ?? LocalAuthentication();
  final LocalAuthentication _a;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _a.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _a.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }
}

class LockState {
  const LockState({required this.enabled, required this.locked, this.timeout = const Duration(minutes: 1), this.failed = false});
  final bool enabled;
  final bool locked;
  final Duration timeout;
  final bool failed;
  LockState copyWith({bool? enabled, bool? locked, Duration? timeout, bool? failed}) =>
      LockState(enabled: enabled ?? this.enabled, locked: locked ?? this.locked, timeout: timeout ?? this.timeout, failed: failed ?? this.failed);
}

/// Locks the UI after [timeout] in the background. Locking never touches data or sync; it
/// only gates the screen (the DB key is held by the OS secure store).
class AppLockController extends Notifier<LockState> {
  AppLockController({required this.authenticator, DateTime Function()? now, this._startEnabled = false, this.persistEnabled})
      : _now = now ?? DateTime.now;

  /// Persists the setting (so it survives restarts).
  final Future<void> Function(bool enabled)? persistEnabled;

  final Authenticator authenticator;
  final DateTime Function() _now;
  final bool _startEnabled;
  DateTime? _backgroundedAt;

  @override
  LockState build() => LockState(enabled: _startEnabled, locked: _startEnabled);

  Future<bool> setEnabled(bool enable) async {
    if (enable == state.enabled) return true;
    // Require a successful check before turning ON, so users can't lock themselves out
    // with a method that doesn't work on this device; and before turning OFF, so a borrowed
    // unlocked phone can't disable it.
    if (!await authenticator.isAvailable()) return false;
    if (!await authenticator.authenticate(enable ? 'Confirm to turn on app lock' : 'Confirm to turn off app lock')) return false;
    await persistEnabled?.call(enable);
    state = state.copyWith(enabled: enable, locked: false);
    return true;
  }

  void setTimeout(Duration d) => state = state.copyWith(timeout: d);

  void onBackgrounded() => _backgroundedAt = _now();

  void onResumed() {
    final at = _backgroundedAt;
    _backgroundedAt = null;
    if (state.enabled && at != null && _now().difference(at) >= state.timeout) state = state.copyWith(locked: true, failed: false);
  }

  Future<void> unlock() async {
    final ok = await authenticator.authenticate('Unlock Folio');
    state = state.copyWith(locked: !ok, failed: !ok);
  }
}
