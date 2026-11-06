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
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(at.year, at.month, at.day)).inDays;
  final when = days <= 0 ? 'today' : (days == 1 ? 'yesterday' : '$days days ago');
  return 'Last backup: $when (${dateLabel(at)})';
}

String _mb(int bytes) => bytes >= 1048576 ? '${(bytes / 1048576).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

class BackupTiles extends ConsumerStatefulWidget {
  const BackupTiles({super.key});
  @override
  ConsumerState<BackupTiles> createState() => _BackupTilesState();
}

class _BackupTilesState extends ConsumerState<BackupTiles> {
  bool _busy = false;

  void _say(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _backup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final svc = ref.read(backupServiceProvider);
      final file = await svc.create(await ref.read(backupTempDirProvider)());
      final shared = await ref.read(backupSharerProvider)(file);
      if (shared) {
        await ref.read(syncedStoreProvider).setState(lastBackupKey, '${DateTime.now().millisecondsSinceEpoch}');
        ref.invalidate(lastBackupProvider);
        _say('Backup ready (${_mb(await file.length())}). Keep it somewhere safe.');
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
      final info = await svc.inspect(path);
      if (!mounted) return;
      setState(() => _busy = false); // not working while the dialog waits for the user
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: Text('Made on ${dateLabel(info.createdAt)} at ${timeLabel(info.createdAt)} · ${_mb(info.sizeBytes)}\n\n'
              '${info.tasks} tasks · ${info.events} events · ${info.books} books · ${info.shelves} shelves\n\n'
              'Restoring only adds what is missing on this device. Nothing here is deleted or replaced.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(key: const Key('restore-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _busy = true);
      final r = await svc.restore(path);
      if (!mounted) return;
      setState(() => _busy = false);
      await ref.read(plannerControllerProvider.notifier).refresh();
      ref.invalidate(dataSummaryProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(r.added == 0 && r.problems.isEmpty ? 'Nothing to add' : 'Restore finished'),
          content: Text([
            if (r.added > 0) 'Added ${r.tasks} tasks, ${r.events} events, ${r.books} books and ${r.shelves} shelves.',
            if (r.added == 0 && r.problems.isEmpty) 'Everything in this backup is already on this device.',
            if (r.skipped > 0 && r.added > 0) '${r.skipped} items were already here and left untouched.',
            if (r.problems.isNotEmpty) 'Problems:\n${r.problems.map((p) => '• $p').join('\n')}',
          ].join('\n\n')),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
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
    return Column(children: [
      ListTile(
        key: const Key('backup-status'),
        leading: Icon(Icons.shield_outlined, color: last == null ? context.colors.warn : context.colors.ok),
        title: Text(backupAge(last, DateTime.now())),
        subtitle: Text('${sum == null ? '' : '${sum.tasks} tasks · ${sum.events} events · ${sum.books} books on this device.\n'}'
            'The backup is one file. It is not encrypted, so keep it somewhere private.'),
      ),
      Padding(
        padding: const EdgeInsets.all(Space.s16),
        child: Wrap(spacing: Space.s8, runSpacing: Space.s8, children: [
          FilledButton.icon(
            key: const Key('backup-now'),
            onPressed: _busy ? null : _backup,
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.ios_share),
            label: Text(_busy ? 'Working…' : 'Back up now'),
          ),
          OutlinedButton.icon(key: const Key('backup-restore'), onPressed: _busy ? null : _restore, icon: const Icon(Icons.restore), label: const Text('Restore from a file')),
        ]),
      ),
    ]);
  }
}
