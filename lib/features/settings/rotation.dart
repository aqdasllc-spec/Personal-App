import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

enum RotationMode { auto, portrait }

abstract interface class OrientationLock {
  Future<void> apply(RotationMode mode);
}

/// Phones and tablets only; desktop windows ignore it.
class SystemOrientationLock implements OrientationLock {
  @override
  Future<void> apply(RotationMode mode) =>
      SystemChrome.setPreferredOrientations(
        mode == RotationMode.portrait
            ? const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ]
            : DeviceOrientation.values,
      );
}

final orientationLockProvider = Provider<OrientationLock>(
  (ref) => SystemOrientationLock(),
);

const _storageKey = 'rotation_mode';

Future<RotationMode> loadRotationMode(
  Future<String?> Function(String key) read,
) async => (await read(_storageKey)) == 'portrait'
    ? RotationMode.portrait
    : RotationMode.auto;

class RotationController extends Notifier<RotationMode> {
  RotationController([this.initial = RotationMode.auto]);
  final RotationMode initial;

  @override
  RotationMode build() => initial;

  Future<void> set(RotationMode mode) async {
    state = mode;
    await ref.read(syncedStoreProvider).setState(_storageKey, mode.name);
    await ref.read(orientationLockProvider).apply(mode);
  }
}

final rotationProvider = NotifierProvider<RotationController, RotationMode>(
  RotationController.new,
);
