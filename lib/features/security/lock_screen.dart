import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';

class LockScreen extends ConsumerWidget {
  const LockScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    return Scaffold(
      body: EmptyState(
        icon: Icons.lock_outline,
        title: 'Folio is locked',
        message: lock.failed ? 'Couldn\'t verify it\'s you. Try again.' : 'Unlock to continue. Your data stays on this device.',
        actionLabel: 'Unlock',
        onAction: () => ref.read(appLockProvider.notifier).unlock(),
      ),
    );
  }
}
