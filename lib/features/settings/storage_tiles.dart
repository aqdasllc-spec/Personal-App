import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../design_system/tokens.dart';
import '../library/application/book_sync.dart';
import '../library/application/covers.dart';
import '../library/application/library_controller.dart';
import '../library/data/library_repository.dart';
import '../library/domain_format.dart';

/// Cloud storage of the free plan, used only to show a meter. Your plan may differ.
const freeCloudBytes = 1024 * 1024 * 1024;

final storageReportProvider = FutureProvider.autoDispose<StorageReport>((ref) async {
  // recompute whenever books change (added, removed, synced...)
  ref.watch(booksProvider);
  return ref.watch(libraryRepositoryProvider).storageReport();
});

/// Settings -> Storage: what the library uses on this phone and in the cloud, and ways to free space.
class StorageTiles extends ConsumerWidget {
  const StorageTiles({super.key});

  void _say(BuildContext context, String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(storageReportProvider);
    final cloudOn = ref.watch(cloudBooksProvider) != null;
    final t = Theme.of(context).textTheme;
    return report.when(
      loading: () => const Padding(padding: EdgeInsets.all(Space.s16), child: LinearProgressIndicator()),
      error: (e, _) => ListTile(title: const Text('Couldn\'t read the storage use'), subtitle: Text('$e')),
      data: (r) {
        final used = r.cloudBytes / freeCloudBytes;
        return Column(children: [
          ListTile(
            key: const Key('storage-device'),
            leading: const Icon(Icons.phone_android),
            title: const Text('On this phone'),
            subtitle: Text('${r.bookCount} ${r.bookCount == 1 ? 'book' : 'books'} · ${formatBytes(r.bookBytes)}'),
          ),
          if (cloudOn)
            ListTile(
              key: const Key('storage-cloud'),
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('In your cloud'),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r.cloudCount} ${r.cloudCount == 1 ? 'book' : 'books'} · ${formatBytes(r.cloudBytes)} of ${formatBytes(freeCloudBytes)} (free plan; yours may differ)'),
                const SizedBox(height: Space.s4),
                LinearProgressIndicator(
                  key: const Key('storage-cloud-meter'),
                  value: used.clamp(0.0, 1.0),
                  color: used > .8 ? context.colors.warn : null,
                  minHeight: 6,
                ),
              ]),
              isThreeLine: true,
            ),
          if (cloudOn && r.cloudCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: Space.s16),
                child: TextButton.icon(
                  key: const Key('storage-unsync-all'),
                  icon: const Icon(Icons.cloud_off_outlined, size: 18),
                  label: const Text('Remove all cloud copies'),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Remove all cloud copies?'),
                        content: Text('This deletes ${r.cloudCount} ${r.cloudCount == 1 ? 'book' : 'books'} (${formatBytes(r.cloudBytes)}) from your cloud. They all stay on this phone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(key: const Key('storage-unsync-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove cloud copies')),
                        ],
                      ),
                    );
                    if (ok != true || !context.mounted) return;
                    final ctl = ref.read(bookSyncProvider.notifier);
                    final synced = [for (final b in ref.read(booksProvider).value ?? const <BookRow>[]) if (b.cloudState == 'synced') b];
                    var done = 0;
                    for (final b in synced) {
                      if (await ctl.unsync(b)) done++;
                    }
                    ctl.clearMessage();
                    ref.invalidate(storageReportProvider);
                    if (context.mounted) {
                      _say(context, done == synced.length ? 'Removed $done cloud ${done == 1 ? 'copy' : 'copies'}.' : 'Removed $done of ${synced.length}. The rest could not be reached; try again when you are online.');
                    }
                  },
                ),
              ),
            ),
          ListTile(
            key: const Key('storage-covers'),
            leading: const Icon(Icons.image_outlined),
            title: const Text('Cover previews'),
            subtitle: Text('${formatBytes(r.coverBytes)} · first pages kept so previews open fast; they are rebuilt when needed'),
            trailing: TextButton(
              key: const Key('storage-clear-covers'),
              onPressed: r.coverBytes == 0
                  ? null
                  : () async {
                      final freed = await ref.read(libraryRepositoryProvider).clearCovers();
                      ref.invalidate(coverBytesProvider);
                      ref.invalidate(storageReportProvider);
                      if (context.mounted) _say(context, 'Freed ${formatBytes(freed)}.');
                    },
              child: const Text('Clear'),
            ),
          ),
          if (r.removedCount > 0)
            ListTile(
              key: const Key('storage-removed'),
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Removed books not yet deleted'),
              subtitle: Text('${r.removedCount} ${r.removedCount == 1 ? 'book' : 'books'} · ${formatBytes(r.removedBytes)} · deleted for good the next time the app starts'),
              trailing: TextButton(
                key: const Key('storage-purge'),
                onPressed: () async {
                  final n = await ref.read(libraryRepositoryProvider).purge();
                  ref.invalidate(storageReportProvider);
                  if (context.mounted) _say(context, 'Deleted $n ${n == 1 ? 'book' : 'books'} for good.');
                },
                child: const Text('Delete now'),
              ),
            ),
          if (r.largest.isNotEmpty)
            ExpansionTile(
              key: const Key('storage-largest'),
              leading: const Icon(Icons.bar_chart),
              title: const Text('Largest books'),
              children: [
                for (final b in r.largest)
                  ListTile(
                    key: Key('storage-book-${b.id}'),
                    dense: true,
                    title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (b.cloudState == 'synced') const Padding(padding: EdgeInsets.only(right: Space.s8), child: Icon(Icons.cloud_done_outlined, size: 16)),
                      Text(formatBytes(b.sizeBytes), style: t.bodySmall),
                    ]),
                  ),
              ],
            ),
        ]);
      },
    );
  }
}
