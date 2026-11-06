import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/tokens.dart';
import '../../app/providers.dart';
import '../backup/backup_controller.dart';
import '../backup/backup_service.dart';
import '../planner/application/planner_controller.dart';
import '../planner/presentation/format.dart';

String backupAge(DateTime? at, DateTime now) {
  if (at == null) return 'Never backed up';
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  final when = days <= 0
      ? 'today'
      : (days == 1 ? 'yesterday' : '$days days ago');
  return 'Last backup: $when (${dateLabel(at)})';
}

String _mb(int bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).ceil()} KB';

class BackupTiles extends ConsumerStatefulWidget {
  const BackupTiles({super.key});
  @override
  ConsumerState<BackupTiles> createState() => _BackupTilesState();
}

class _BackupTilesState extends ConsumerState<BackupTiles> {
  bool _busy = false;

  void _say(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _backup() async {
    if (_busy) return;
    // null = cancelled, '' = no password, otherwise the chosen password
    final pw = await showDialog<String>(
      context: context,
      builder: (_) => const _SetPasswordDialog(),
    );
    if (pw == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final svc = ref.read(backupServiceProvider);
      final file = await svc.create(
        await ref.read(backupTempDirProvider)(),
        password: pw.isEmpty ? null : pw,
      );
      final shared = await ref.read(backupSharerProvider)(file);
      if (shared) {
        await ref
            .read(syncedStoreProvider)
            .setState(
              lastBackupKey,
              '${DateTime.now().millisecondsSinceEpoch}',
            );
        ref.invalidate(lastBackupProvider);
        _say(
          'Backup ready (${_mb(await file.length())})${pw.isEmpty ? '' : ', password protected'}. Keep it somewhere safe.',
        );
      } else {
        _say('Backup cancelled. Nothing was saved.');
      }
    } catch (e) {
      _say('Couldn\'t create the backup: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final path = await ref.read(backupPickerProvider)();
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final svc = ref.read(backupServiceProvider);
      String? password;
      BackupInfo? info;
      if (await svc.isEncrypted(path)) {
        // keep asking until the password fits or the user gives up
        var wrong = false;
        while (info == null) {
          if (!mounted) return;
          setState(() => _busy = false);
          password = await showDialog<String>(
            context: context,
            builder: (_) => _AskPasswordDialog(wrong: wrong),
          );
          if (password == null || !mounted) return;
          setState(() => _busy = true);
          try {
            info = await svc.inspect(path, password: password);
          } on BackupWrongPassword {
            wrong = true;
          }
        }
      } else {
        info = await svc.inspect(path);
      }
      if (!mounted) return;
      setState(
        () => _busy = false,
      ); // not working while the dialog waits for the user
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: Text(
            'Made on ${dateLabel(info!.createdAt)} at ${timeLabel(info.createdAt)} · ${_mb(info.sizeBytes)}${info.encrypted ? ' · password protected' : ''}\n\n'
            '${info.tasks} tasks · ${info.events} events · ${info.books} books · ${info.shelves} shelves\n\n'
            'Restoring only adds what is missing on this device. Nothing here is deleted or replaced.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('restore-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _busy = true);
      final r = await svc.restore(path, password: password);
      if (!mounted) return;
      setState(() => _busy = false);
      await ref.read(plannerControllerProvider.notifier).refresh();
      ref.invalidate(dataSummaryProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            r.added == 0 && r.problems.isEmpty
                ? 'Nothing to add'
                : 'Restore finished',
          ),
          content: Text(
            [
              if (r.added > 0)
                'Added ${r.tasks} tasks, ${r.events} events, ${r.books} books and ${r.shelves} shelves.',
              if (r.added == 0 && r.problems.isEmpty)
                'Everything in this backup is already on this device.',
              if (r.skipped > 0 && r.added > 0)
                '${r.skipped} items were already here and left untouched.',
              if (r.problems.isNotEmpty)
                'Problems:\n${r.problems.map((p) => '• $p').join('\n')}',
            ].join('\n\n'),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on BackupException catch (e) {
      _say(e.message);
    } catch (e) {
      _say('Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = ref.watch(lastBackupProvider).value;
    final sum = ref.watch(dataSummaryProvider).value;
    return Column(
      children: [
        ListTile(
          key: const Key('backup-status'),
          leading: Icon(
            Icons.shield_outlined,
            color: last == null ? context.colors.warn : context.colors.ok,
          ),
          title: Text(backupAge(last, DateTime.now())),
          subtitle: Text(
            '${sum == null ? '' : '${sum.tasks} tasks · ${sum.events} events · ${sum.books} books on this device.\n'}'
            'The backup is one file. You can protect it with a password when you make it; without one it is not encrypted, so keep it somewhere private.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.s16),
          child: Wrap(
            spacing: Space.s8,
            runSpacing: Space.s8,
            children: [
              FilledButton.icon(
                key: const Key('backup-now'),
                onPressed: _busy ? null : _backup,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share),
                label: Text(_busy ? 'Working…' : 'Back up now'),
              ),
              OutlinedButton.icon(
                key: const Key('backup-restore'),
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore),
                label: const Text('Restore from a file'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Asks whether to protect a new backup with a password. Pops null (cancel), '' (no password) or the password.
class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog();
  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final _a = TextEditingController(), _b = TextEditingController();
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _encrypt() {
    if (_a.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
    } else if (_a.text != _b.text) {
      setState(() => _error = 'The two passwords don\'t match.');
    } else {
      Navigator.pop(context, _a.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Protect with a password?'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Optional. An encrypted backup cannot be opened without the password, and nobody can recover it for you — if you forget it, the backup is lost.',
          ),
          const SizedBox(height: Space.s12),
          TextField(
            key: const Key('backup-password'),
            controller: _a,
            obscureText: !_show,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          TextField(
            key: const Key('backup-password2'),
            controller: _b,
            obscureText: !_show,
            decoration: InputDecoration(
              labelText: 'Repeat password',
              errorText: _error,
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _show,
            onChanged: (v) => setState(() => _show = v ?? false),
            title: const Text('Show password'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const Key('backup-cancel'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('backup-no-password'),
        onPressed: () => Navigator.pop(context, ''),
        child: const Text('No password'),
      ),
      FilledButton(
        key: const Key('backup-encrypt'),
        onPressed: _encrypt,
        child: const Text('Encrypt'),
      ),
    ],
  );
}

class _AskPasswordDialog extends StatefulWidget {
  const _AskPasswordDialog({required this.wrong});
  final bool wrong;
  @override
  State<_AskPasswordDialog> createState() => _AskPasswordDialogState();
}

class _AskPasswordDialogState extends State<_AskPasswordDialog> {
  final _c = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Password needed'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('This backup is password protected.'),
        TextField(
          key: const Key('restore-password'),
          controller: _c,
          autofocus: true,
          obscureText: !_show,
          decoration: InputDecoration(
            labelText: 'Password',
            errorText: widget.wrong
                ? 'Wrong password, or the file is damaged.'
                : null,
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _show,
          onChanged: (v) => setState(() => _show = v ?? false),
          title: const Text('Show password'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('restore-password-ok'),
        onPressed: () => Navigator.pop(context, _c.text),
        child: const Text('Open'),
      ),
    ],
  );
}
