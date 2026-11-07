import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../design_system/tokens.dart';
import '../library/application/library_controller.dart';
import '../library/data/library_repository.dart';
import '../library/domain_format.dart';

final removedBooksProvider = StreamProvider.autoDispose<List<BookRow>>((ref) => ref.watch(libraryRepositoryProvider).watchRemoved());

String _removedAgo(int deletedAtMs, DateTime now) {
  final days = now.difference(DateTime.fromMillisecondsSinceEpoch(deletedAtMs)).inDays;
  return days <= 0 ? 'Removed today' : (days == 1 ? 'Removed yesterday' : 'Removed $days days ago');
}

String daysLeftLabel(int left) => left <= 0 ? 'deleted for good soon' : (left == 1 ? '1 day left' : '$left days left');

/// The bin: books removed in the last 30 days. Restore one, delete one for good, or empty the bin.
class RemovedBooksSheet extends ConsumerWidget {
  const RemovedBooksSheet({super.key, this.now});

  /// The clock (tests pass a fixed one).
  final DateTime Function()? now;

  void _say(BuildContext context, String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final removed = ref.watch(removedBooksProvider).value ?? const <BookRow>[];
    final repo = ref.read(libraryRepositoryProvider);
    final clock = (now ?? DateTime.now)();
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s8, Space.s8),
            child: Row(children: [
              Expanded(child: Text('Recently removed', style: t.titleMedium)),
              if (removed.isNotEmpty)
                TextButton(
                  key: const Key('bin-empty'),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Empty the bin?'),
                        content: Text('${removed.length} ${removed.length == 1 ? 'book' : 'books'} (${formatBytes(removed.fold(0, (n, b) => n + b.sizeBytes))}) will be deleted for good, with their bookmarks and highlights.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(key: const Key('bin-empty-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete for good')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    final n = await repo.purge();
                    if (context.mounted) _say(context, 'Deleted $n ${n == 1 ? 'book' : 'books'} for good.');
                  },
                  child: const Text('Empty bin'),
                ),
            ]),
          ),
          if (removed.isEmpty)
            const Padding(padding: EdgeInsets.fromLTRB(Space.s24, Space.s16, Space.s24, Space.s32), child: Text('Nothing here. Books you remove stay here for 30 days before they are deleted for good.', textAlign: TextAlign.center))
          else
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final b in removed)
                  ListTile(
                    key: Key('bin-${b.id}'),
                    title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${_removedAgo(b.deletedAt!, clock)} · ${daysLeftLabel(binDaysLeft(b.deletedAt!, clock))} · ${formatBytes(b.sizeBytes)}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        key: Key('bin-restore-${b.id}'),
                        tooltip: 'Restore',
                        icon: const Icon(Icons.restore),
                        onPressed: () async {
                          await repo.restore(b.id);
                          if (context.mounted) _say(context, 'Restored "${b.title}".');
                        },
                      ),
                      IconButton(
                        key: Key('bin-delete-${b.id}'),
                        tooltip: 'Delete for good',
                        icon: const Icon(Icons.delete_forever_outlined),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('Delete "${b.title}" for good?'),
                              content: const Text('This cannot be undone.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                FilledButton(key: const Key('bin-delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                              ],
                            ),
                          );
                          if (ok == true) await repo.deletePermanently(b.id);
                        },
                      ),
                    ]),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
