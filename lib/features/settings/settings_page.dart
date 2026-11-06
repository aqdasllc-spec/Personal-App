import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../design_system/tokens.dart';
import '../auth/auth_repository.dart';

/// Phase 1 settings: only what actually works today (account, sync, app lock).
/// Backup, appearance, AI and notifications are added with their features.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider).value ?? ref.watch(authRepositoryProvider).current;
    final sync = ref.watch(syncControllerProvider);
    final lock = ref.watch(appLockProvider);

    String when(DateTime? d) => d == null ? 'never' : '${d.toLocal()}'.split('.').first;

    return ListView(padding: const EdgeInsets.all(Space.s24), children: [
      Text('Settings', style: t.displaySmall),
      const SizedBox(height: Space.s24),
      _Section('Account', [
        ListTile(
          title: Text(switch (session) { SignedInSession s => s.email, LocalOnlySession _ => 'Local only (no account)', SignedOutSession _ => 'Signed out' }),
          subtitle: Text(session is LocalOnlySession ? 'Data stays on this device.' : 'Cloud sync enabled.'),
          trailing: session is SignedInSession ? TextButton(onPressed: () => ref.read(authRepositoryProvider).signOut(), child: const Text('Sign out')) : null,
        ),
      ]),
      _Section('Sync', [
        ListTile(title: const Text('Status'), trailing: SyncChip(phase: sync.phase, pending: sync.pending)),
        ListTile(title: const Text('Last successful sync'), subtitle: Text(when(sync.lastSync))),
        if (sync.error != null) ListTile(title: const Text('Last problem'), subtitle: Text(sync.error!)),
        ListTile(
          title: const Text('Sync now'),
          enabled: sync.phase != SyncPhase.localOnly,
          trailing: const Icon(Icons.sync),
          onTap: sync.phase == SyncPhase.localOnly ? null : () => ref.read(syncControllerProvider.notifier).syncNow(),
        ),
      ]),
      _Section('Security', [
        SwitchListTile(
          title: const Text('App lock'),
          subtitle: const Text('Require Face ID / fingerprint / Windows Hello / device passcode after the app was in the background.'),
          value: lock.enabled,
          onChanged: (v) async {
            final ok = await ref.read(appLockProvider.notifier).setEnabled(v);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t verify with this device, so app lock was left unchanged.')));
            }
          },
        ),
      ]),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.s24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.s8),
          Card(child: Column(children: children)),
        ]),
      );
}
