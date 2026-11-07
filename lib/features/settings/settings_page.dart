import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../design_system/tokens.dart';
import '../auth/auth_repository.dart';
import 'backup_tiles.dart';
import 'notifications_tiles.dart';
import '../welcome/welcome_page.dart';
import 'storage_tiles.dart';
import 'rotation.dart';

/// Phase 1 settings: only what actually works today (account, sync, app lock).
/// Backup, appearance, AI and notifications are added with their features.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final session =
        ref.watch(sessionProvider).value ??
        ref.watch(authRepositoryProvider).current;
    final sync = ref.watch(syncControllerProvider);
    final lock = ref.watch(appLockProvider);
    final rotation = ref.watch(rotationProvider);
    final mobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    String when(DateTime? d) =>
        d == null ? 'never' : '${d.toLocal()}'.split('.').first;

    return ListView(
      padding: const EdgeInsets.all(Space.s24),
      children: [
        Text('Settings', style: t.displaySmall),
        const SizedBox(height: Space.s24),
        _Section('Account', [
          ListTile(
            title: Text(switch (session) {
              SignedInSession s => s.email,
              LocalOnlySession _ => 'Local only (no account)',
              SignedOutSession _ => 'Signed out',
            }),
            // the button sits under the text so it never squeezes it (large text sizes)
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session is LocalOnlySession
                      ? 'Data stays on this device.'
                      : 'Cloud sync enabled.',
                ),
                if (session is SignedInSession)
                  TextButton(
                    onPressed: () => ref.read(authRepositoryProvider).signOut(),
                    child: const Text('Sign out'),
                  )
                else if (session is LocalOnlySession &&
                    ref.read(authRepositoryProvider).cloudAvailable)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s8),
                    child: FilledButton(
                      key: const Key('settings-sign-in'),
                      onPressed: () =>
                          ref.read(authRepositoryProvider).leaveLocalOnly(),
                      child: const Text('Sign in to sync'),
                    ),
                  ),
              ],
            ),
          ),
        ]),
        _Section('Sync', [
          ListTile(
            title: const Text('Status'),
            trailing: SyncChip(phase: sync.phase, pending: sync.pending),
          ),
          ListTile(
            title: const Text('Last successful sync'),
            subtitle: Text(when(sync.lastSync)),
          ),
          if (sync.error != null)
            ListTile(
              title: const Text('Last problem'),
              subtitle: Text(sync.error!),
            ),
          ListTile(
            title: const Text('Sync now'),
            enabled: sync.phase != SyncPhase.localOnly,
            trailing: const Icon(Icons.sync),
            onTap: sync.phase == SyncPhase.localOnly
                ? null
                : () => ref.read(syncControllerProvider.notifier).syncNow(),
          ),
        ]),
        if (mobile)
          _Section('Display', [
            Padding(
              padding: const EdgeInsets.all(Space.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Screen rotation',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: Space.s4),
                  Text(
                    'Portrait only keeps the app upright even when you turn the phone.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: Space.s12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<RotationMode>(
                      key: const Key('rotation'),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: RotationMode.auto,
                          label: Text('Auto'),
                        ),
                        ButtonSegment(
                          value: RotationMode.portrait,
                          label: Text('Portrait'),
                        ),
                      ],
                      selected: {rotation},
                      onSelectionChanged: (s) =>
                          ref.read(rotationProvider.notifier).set(s.first),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        _Section('Notifications', const [NotificationsTiles()]),
        _Section('Backup', const [BackupTiles()]),
        _Section('Storage', const [StorageTiles()]),
        _Section('Help', const [HelpTiles()]),
        _Section('Security', [
          SwitchListTile(
            title: const Text('App lock'),
            subtitle: const Text(
              'Require Face ID / fingerprint / Windows Hello / device passcode after the app was in the background.',
            ),
            value: lock.enabled,
            onChanged: (v) async {
              final ok = await ref.read(appLockProvider.notifier).setEnabled(v);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Couldn\'t verify with this device, so app lock was left unchanged.',
                    ),
                  ),
                );
              }
            },
          ),
        ]),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Space.s8),
        Card(child: Column(children: children)),
      ],
    ),
  );
}
