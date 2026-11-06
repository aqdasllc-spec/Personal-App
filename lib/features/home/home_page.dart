import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/local/app_database.dart';
import '../../design_system/components.dart';
import '../../design_system/tokens.dart';
import '../backup/backup_controller.dart';
import '../library/application/library_controller.dart';
import '../library/presentation/book_visuals.dart';
import '../planner/application/planner_controller.dart';
import '../planner/domain/agenda.dart';
import '../planner/presentation/format.dart';
import '../planner/presentation/planner_widgets.dart';

/// Home: what needs attention today, what is coming up, and where you stopped reading.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final planner = ref.watch(plannerControllerProvider);
    final books = ref.watch(booksProvider).value ?? const <BookRow>[];
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: planner.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EmptyState(icon: Icons.error_outline, title: 'Couldn\'t load Home', message: '$e'),
          data: (s) {
            final today = s.today;
            final agenda = dayAgenda(today, s.tasks, s.events, today: today);
            final upcoming = _upcoming(s, today);
            final cards = <Widget>[
              _TodayCard(agenda: agenda, today: today),
              if (upcoming.isNotEmpty) _UpcomingCard(items: upcoming),
              _ReadingCard(books: books),
            ];
            return ListView(
              padding: const EdgeInsets.all(Space.s16),
              children: [
                _Header(today: today),
                const SizedBox(height: Space.s16),
                const _QuickAdd(),
                const SizedBox(height: Space.s16),
                const _BackupNudge(),
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: Space.s16),
                    Expanded(child: Column(children: [for (final w in cards.skip(1)) Padding(padding: const EdgeInsets.only(bottom: Space.s16), child: w)])),
                  ])
                else
                  for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: Space.s16), child: w),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Open tasks and timed events for the next 7 days (after today), earliest first, at most 6.
  static List<({DateTime day, AgendaItem item})> _upcoming(PlannerState s, DateTime today) {
    final out = <({DateTime day, AgendaItem item})>[];
    for (var i = 1; i <= 7 && out.length < 6; i++) {
      final day = addDays(dateOnly(today), i);
      final a = dayAgenda(day, s.tasks, s.events, today: today);
      for (final it in [...a.allDay, ...a.timed.where((x) => x.kind == ItemKind.event), ...a.tasks.where((x) => !x.done)]) {
        if (out.length < 6) out.add((day: day, item: it));
      }
    }
    return out;
  }
}

String greeting(DateTime now) => now.hour < 12 ? 'Good morning' : (now.hour < 18 ? 'Good afternoon' : 'Good evening');

class _Header extends StatelessWidget {
  const _Header({required this.today});
  final DateTime today;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(greeting(DateTime.now()), style: t.headlineSmall?.copyWith(fontFamily: 'serif')),
      Text('${weekdayLong(today.weekday)} ${today.day} ${monthLong(today.month)}', style: t.bodyMedium?.copyWith(color: context.colors.textMuted)),
    ]);
  }
}

class _QuickAdd extends ConsumerStatefulWidget {
  const _QuickAdd();
  @override
  ConsumerState<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends ConsumerState<_QuickAdd> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    final ctrl = ref.read(plannerControllerProvider.notifier);
    final today = ref.read(plannerControllerProvider).value?.today;
    final id = await ctrl.quickAdd(text, due: today);
    if (id != null) _c.clear();
  }

  @override
  Widget build(BuildContext context) => TextField(
        key: const Key('home-quick-add'),
        controller: _c,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Add a task for today…',
          prefixIcon: const Icon(Icons.add),
          suffixIcon: IconButton(key: const Key('home-quick-add-go'), tooltip: 'Add task', icon: const Icon(Icons.keyboard_return), onPressed: _submit),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.input)),
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children, this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Space.s16),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.card), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: Space.s8),
        ...children,
      ]),
    );
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.agenda, required this.today});
  final DayAgenda agenda;
  final DateTime today;
  static const _max = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final open = agenda.tasks.where((x) => !x.done).length;
    final done = agenda.tasks.length - open;
    final events = [...agenda.allDay, ...agenda.timed.where((x) => x.kind == ItemKind.event)];
    void openPlanner() {
      ref.read(plannerControllerProvider.notifier).openDay(today);
      context.go(Routes.planner);
    }

    final shown = agenda.tasks.take(_max).toList();
    final empty = agenda.tasks.isEmpty && agenda.overdue.isEmpty && events.isEmpty;
    return _Card(
      title: 'Today',
      trailing: TextButton(key: const Key('home-open-planner'), onPressed: openPlanner, child: const Text('Open planner')),
      children: [
        if (empty) Text('Nothing planned for today. Add a task above, or enjoy the free day.', style: t.bodySmall),
        if (agenda.overdue.isNotEmpty) ...[
          Text('${agenda.overdue.length} overdue', key: const Key('home-overdue'), style: t.labelLarge?.copyWith(color: context.colors.danger)),
          for (final i in agenda.overdue.take(3)) TaskTile(item: i, showDate: true, onOpen: openPlanner),
          const SizedBox(height: Space.s8),
        ],
        for (final e in events)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s4),
            child: Row(children: [
              const Icon(Icons.event, size: 18),
              const SizedBox(width: Space.s8),
              Expanded(child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(e.allDay || e.start == null ? 'All day' : timeLabel(e.start!), style: t.bodySmall),
            ]),
          ),
        for (final i in shown) TaskTile(item: i, onOpen: openPlanner),
        if (agenda.tasks.length > _max) TextButton(onPressed: openPlanner, child: Text('${agenda.tasks.length - _max} more')),
        if (agenda.tasks.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Space.s4), child: Text('$done of ${agenda.tasks.length} done', key: const Key('home-progress'), style: t.bodySmall)),
      ],
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.items});
  final List<({DateTime day, AgendaItem item})> items;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _Card(title: 'Coming up', children: [
      for (final e in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s4),
          child: Row(children: [
            SizedBox(width: 64, child: Text('${weekdayShort(e.day.weekday)} ${e.day.day}', style: t.labelLarge)),
            Icon(e.item.kind == ItemKind.event ? Icons.event : Icons.radio_button_unchecked, size: 16),
            const SizedBox(width: Space.s8),
            Expanded(child: Text(e.item.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (e.item.hasTime && e.item.start != null) Text(timeLabel(e.item.start!), style: t.bodySmall),
          ]),
        ),
    ]);
  }
}

class _ReadingCard extends ConsumerWidget {
  const _ReadingCard({required this.books});
  final List<BookRow> books;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final recent = recentBooks(books, limit: 6);
    return _Card(
      title: 'Continue reading',
      trailing: TextButton(key: const Key('home-open-library'), onPressed: () => context.go(Routes.library), child: Text(books.isEmpty ? 'Add PDFs' : 'Library')),
      children: [
        if (books.isEmpty)
          Text('Your library is empty. Add a PDF and it will show up here.', style: t.bodySmall)
        else if (recent.isEmpty)
          Text('You haven\'t opened a book yet. ${books.length} ${books.length == 1 ? 'book is' : 'books are'} waiting in your library.', style: t.bodySmall)
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: Space.s12),
              itemBuilder: (_, i) {
                final b = recent[i];
                return InkWell(
                  key: Key('home-book-${b.id}'),
                  borderRadius: BorderRadius.circular(Radii.input),
                  onTap: () => context.push('${Routes.library}/read/${b.id}'),
                  child: SizedBox(
                    width: 96,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      CoverTile(book: b, size: 88),
                      const SizedBox(height: Space.s4),
                      Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                      LinearProgressIndicator(value: readingProgress(b), minHeight: 3),
                    ]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Reminds you to back up once there is something worth losing (never backed up, or not for 14 days).
class _BackupNudge extends ConsumerWidget {
  const _BackupNudge();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sum = ref.watch(dataSummaryProvider).value;
    final last = ref.watch(lastBackupProvider);
    if (sum == null || last.isLoading) return const SizedBox.shrink();
    final has = sum.tasks + sum.events + sum.books > 0;
    final stale = last.value == null || DateTime.now().difference(last.value!).inDays >= 14;
    if (!has || !stale) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s16),
      child: Container(
        key: const Key('home-backup-nudge'),
        padding: const EdgeInsets.all(Space.s12),
        decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.card)),
        child: Row(children: [
          const Icon(Icons.shield_outlined),
          const SizedBox(width: Space.s12),
          Expanded(child: Text(last.value == null ? 'Your data lives only on this device. Make a backup.' : 'It has been a while since your last backup.')),
          TextButton(onPressed: () => context.go(Routes.settings), child: const Text('Back up')),
        ]),
      ),
    );
  }
}
