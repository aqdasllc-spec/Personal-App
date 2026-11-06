import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker_engine/tracker_engine.dart' as te;

import '../../../design_system/components.dart';
import '../../../design_system/tokens.dart';
import '../application/tracker_controller.dart';
import 'prompt_dialog.dart';
import 'tracker_screen.dart';

/// Goals & Projects: the list of the user's trackers and the open tracker.
class TrackersPage extends ConsumerWidget {
  const TrackersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackers = ref.watch(trackersProvider);
    final selected = ref.watch(selectedTrackerProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return trackers.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const EmptyState(icon: Icons.error_outline, title: 'Couldn\'t load your trackers', message: 'Your data is safe. Restart the app to try again.'),
      data: (list) {
        final current = list.where((t) => t.id == selected).firstOrNull ?? (wide ? list.firstOrNull : null);
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.track_changes_outlined,
            title: 'Build your own trackers',
            message: 'Goals, reading lists, budgets, habits — you decide the columns. Start from a template or a blank tracker.',
            actionLabel: 'New tracker',
            onAction: () => showNewTrackerDialog(context, ref),
          );
        }
        final listPane = _TrackerList(trackers: list, selectedId: current?.id);
        final detail = current == null
            ? const EmptyState(icon: Icons.touch_app_outlined, title: 'Pick a tracker', message: 'Choose one from the list.')
            : TrackerScreen(key: ValueKey(current.id), trackerId: current.id, name: current.name, onBack: wide ? null : () => ref.read(selectedTrackerProvider.notifier).select(null));
        if (wide) {
          return Row(children: [
            SizedBox(width: 260, child: listPane),
            VerticalDivider(color: context.colors.border),
            Expanded(child: detail),
          ]);
        }
        return current == null ? listPane : detail;
      },
    );
  }
}

class _TrackerList extends ConsumerWidget {
  const _TrackerList({required this.trackers, required this.selectedId});
  final List<dynamic> trackers;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final repo = ref.read(trackerRepositoryProvider);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s8, Space.s8),
        child: Row(children: [
          Expanded(child: Text('Trackers', style: Theme.of(context).textTheme.titleLarge)),
          IconButton(key: const Key('new-tracker'), tooltip: 'New tracker', onPressed: () => showNewTrackerDialog(context, ref), icon: const Icon(Icons.add)),
        ]),
      ),
      Expanded(
        child: ListView(children: [
          for (final t in trackers)
            ListTile(
              key: Key('tracker-${t.id}'),
              selected: t.id == selectedId,
              selectedTileColor: c.accentSoft,
              leading: const Icon(Icons.table_chart_outlined),
              title: Text(t.name as String, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => ref.read(selectedTrackerProvider.notifier).select(t.id as String),
              trailing: PopupMenuButton<String>(
                tooltip: 'Tracker options',
                onSelected: (a) async {
                  switch (a) {
                    case 'rename':
                      final name = await _promptName(context, t.name as String);
                      if (name != null) await repo.updateTracker(t.id as String, name: name);
                    case 'archive':
                      await repo.archiveTracker(t.id as String, true);
                    case 'delete':
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text('Delete "${t.name}"?'),
                          content: const Text('The tracker and its records will be removed from all your devices.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete'))],
                        ),
                      );
                      if (ok == true) {
                        await repo.deleteTracker(t.id as String);
                        if (selectedId == t.id) ref.read(selectedTrackerProvider.notifier).select(null);
                      }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'archive', child: Text('Archive')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
        ]),
      ),
    ]);
  }
}

Future<String?> _promptName(BuildContext context, String initial) => promptText(context, title: 'Rename tracker', initial: initial, action: 'Rename');

Future<void> showNewTrackerDialog(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(trackerRepositoryProvider);
  final picked = await showDialog<te.TrackerTemplate>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('New tracker'),
      children: [
        for (final t in te.builtInTemplates)
          SimpleDialogOption(
            key: Key('template-${t.id}'),
            onPressed: () => Navigator.pop(dialogContext, t),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: Theme.of(context).textTheme.titleMedium),
              Text(t.description, style: Theme.of(context).textTheme.bodySmall),
              if (t.trackers.length > 1) Text('Creates ${t.trackers.length} linked trackers', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
      ],
    ),
  );
  if (picked == null) return;
  String? firstId;
  if (picked.id == 'blank') {
    if (!context.mounted) return;
    final name = await promptText(context, title: 'Name your tracker', initial: 'Untitled tracker', action: 'Create');
    if (name == null) return;
    firstId = await repo.createTracker(name: name);
  } else {
    firstId = (await repo.createFromTemplate(picked)).first;
  }
  ref.read(selectedTrackerProvider.notifier).select(firstId);
}
