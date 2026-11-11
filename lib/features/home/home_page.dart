import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/quick_actions.dart';
import '../../app/router.dart';
import '../../data/local/app_database.dart';
import '../../design_system/components.dart';
import '../../design_system/tokens.dart';
import '../backup/backup_controller.dart';
import '../library/application/library_controller.dart';
import '../library/domain_reading_stats.dart';
import '../library/presentation/book_peek.dart';
import '../library/presentation/book_visuals.dart';
import '../planner/application/planner_controller.dart';
import '../planner/domain/agenda.dart';
import '../planner/presentation/format.dart';
import '../planner/presentation/planner_widgets.dart';
import '../quran/application/quran_providers.dart' show DailyLang, dailyLangProvider, khatmProvider, quranTodayProvider;
import '../quran/data/quran_data.dart' show QuranData;
import '../quran/domain/khatm.dart';
import '../quran/presentation/quran_cabinet.dart';
import '../quran/presentation/quran_style.dart' show urduText;
import '../welcome/welcome_page.dart';

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
          error: (e, _) => EmptyState(
            icon: Icons.error_outline,
            title: 'Couldn\'t load Home',
            message: '$e',
          ),
          data: (s) {
            final today = s.today;
            final agenda = dayAgenda(today, s.tasks, s.events, today: today);
            final upcoming = _upcoming(s, today);
            final cards = <Widget>[
              _TodayCard(agenda: agenda, today: today),
              if (upcoming.isNotEmpty) _UpcomingCard(items: upcoming),
              _ReadingCard(books: books),
              const _StatsCard(),
            ];
            return ListView(
              padding: const EdgeInsets.all(Space.s16),
              children: [
                const WelcomeGate(),
                _Header(today: today),
                const SizedBox(height: Space.s12),
                const QuranCabinet(),
                const SizedBox(height: Space.s16),
                const _QuickAdd(),
                const SizedBox(height: Space.s16),
                const _BackupNudge(),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: Space.s16),
                      Expanded(
                        child: Column(
                          children: [
                            for (final w in cards.skip(1))
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Space.s16,
                                ),
                                child: w,
                              ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  for (final w in cards)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.s16),
                      child: w,
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Open tasks and timed events for the next 7 days (after today), earliest first, at most 6.
  static List<({DateTime day, AgendaItem item})> _upcoming(
    PlannerState s,
    DateTime today,
  ) {
    final out = <({DateTime day, AgendaItem item})>[];
    for (var i = 1; i <= 7 && out.length < 6; i++) {
      final day = addDays(dateOnly(today), i);
      final a = dayAgenda(day, s.tasks, s.events, today: today);
      for (final it in [
        ...a.allDay,
        ...a.timed.where((x) => x.kind == ItemKind.event),
        ...a.tasks.where((x) => !x.done),
      ]) {
        if (out.length < 6) out.add((day: day, item: it));
      }
    }
    return out;
  }
}

String greeting(DateTime now) => now.hour < 12
    ? 'Good morning'
    : (now.hour < 18 ? 'Good afternoon' : 'Good evening');

class _Header extends ConsumerWidget {
  const _Header({required this.today});
  final DateTime today;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    // with the Quran corner set to Urdu, the greeting is the Islamic one
    final urdu = ref.watch(dailyLangProvider) == DailyLang.urdu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          urdu ? 'السلام علیکم' : greeting(DateTime.now()),
          key: const Key('home-greeting'),
          textDirection: urdu ? TextDirection.rtl : null,
          style: urdu ? urduText(24, color: t.headlineSmall?.color).copyWith(height: 1.6) : t.headlineSmall?.copyWith(fontFamily: 'serif'),
        ),
        Text(
          '${weekdayLong(today.weekday)} ${today.day} ${monthLong(today.month)}',
          style: t.bodyMedium?.copyWith(color: context.colors.textMuted),
        ),
      ],
    );
  }
}

/// Pages read today against the daily goal, the streak and the last seven days.
class _StatsCard extends ConsumerWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(readingStatsProvider).value ?? const <DayStat>[];
    final goal = ref.watch(readGoalProvider);
    final today = ref.watch(plannerControllerProvider).value?.today ?? DateTime.now();
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final days = readingDays(stats);
    final todayPages = stats.where((s) => s.day == dayKey(today)).fold(0, (a, s) => a + s.pages);
    final streak = currentStreak(days, today);
    final week = lastDays(stats, today);
    final weekMax = week.fold(1, (a, b) => b > a ? b : a);
    final weekTime = secondsInLast(stats, today);
    // the Quran: pages read today, next to the khatm goal
    ref.watch(quranTodayProvider);
    final quranPages = ref.read(quranTodayProvider.notifier).countOn(DateTime.now());
    final khatm = ref.watch(khatmProvider);
    final quranRow = quranPages == 0 && khatm == null ? null : _QuranReadRow(pages: quranPages, khatm: khatm);
    return _Card(
      title: 'Reading',
      trailing: TextButton(
        key: const Key('reading-goal-edit'),
        onPressed: () async {
          final v = await showDialog<int>(
            context: context,
            builder: (_) => _GoalDialog(initial: goal),
          );
          if (v != null) ref.read(readGoalProvider.notifier).set(v);
        },
        child: Text('Goal: $goal pages a day'),
      ),
      children: [
        if (quranRow != null) ...[quranRow, const SizedBox(height: Space.s12)],
        if (stats.isEmpty)
          Text('Open a book and read: your pages, streak and daily goal show up here.', key: const Key('stats-empty'), style: t.bodySmall)
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '$todayPages of $goal pages today',
                  key: const Key('stats-today'),
                  style: t.titleSmall,
                ),
              ),
              if (todayPages >= goal) const Icon(Icons.check_circle, color: Color(0xFF30A46C), size: 20),
            ],
          ),
          const SizedBox(height: Space.s8),
          LinearProgressIndicator(value: (todayPages / goal).clamp(0.0, 1.0), minHeight: 8, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: Space.s12),
          Row(
            children: [
              const Icon(Icons.local_fire_department_outlined, size: 20),
              const SizedBox(width: 4),
              Text(
                streak == 0 ? 'No streak yet' : '$streak-day streak',
                key: const Key('stats-streak'),
                style: t.bodyMedium,
              ),
              const Spacer(),
              Text('Best: ${bestStreak(days)}', key: const Key('stats-best'), style: t.bodySmall),
            ],
          ),
          const SizedBox(height: Space.s12),
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < week.length; i++)
                  Expanded(
                    child: Semantics(
                      label: '${week[i]} pages, ${week.length - 1 - i == 0 ? 'today' : '${week.length - 1 - i} days ago'}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Container(
                          key: Key('stats-bar-$i'),
                          height: 4 + 44 * week[i] / weekMax,
                          decoration: BoxDecoration(
                            color: i == week.length - 1 ? Theme.of(context).colorScheme.primary : c.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.s8),
          Text(
            'Last 7 days: ${week.fold(0, (a, b) => a + b)} pages · ${readingTimeLabel(weekTime)} with a book open',
            key: const Key('stats-week'),
            style: t.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// "Quran: N pages today", and the khatm goal: today's portion and how far through it is.
class _QuranReadRow extends StatelessWidget {
  const _QuranReadRow({required this.pages, required this.khatm});
  final int pages;
  final KhatmPlan? khatm;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final k = khatm;
    final today = k == null ? null : khatmToday(k, DateTime.now());
    final portion = today == null
        ? null
        : switch (today.status) {
            KhatmStatus.finished => 'Khatm complete',
            KhatmStatus.doneToday => "Today's portion done ✓",
            KhatmStatus.behind => 'Today: p. ${today.from}–${today.to} (${today.behindBy} behind)',
            KhatmStatus.onTrack => 'Today: p. ${today.from}–${today.to}',
          };
    return InkWell(
      key: const Key('stats-quran'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.go(Routes.quran),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_outlined, size: 20),
                const SizedBox(width: Space.s8),
                Expanded(
                  child: Text(
                    'Quran: $pages ${pages == 1 ? 'page' : 'pages'} today',
                    key: const Key('stats-quran-today'),
                    style: t.titleSmall,
                  ),
                ),
                if (k != null)
                  Text(
                    'Khatm ${k.donePage.clamp(0, QuranData.pageCount)} of ${QuranData.pageCount}',
                    key: const Key('stats-khatm'),
                    style: t.bodySmall?.copyWith(color: c.textMuted),
                  ),
              ],
            ),
            if (k != null) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                key: const Key('stats-khatm-bar'),
                value: k.donePage.clamp(0, QuranData.pageCount) / QuranData.pageCount,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 4),
              Text('${portion!} · day ${today!.day} of ${k.days}', style: t.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({required this.initial});
  final int initial;
  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late int _v = widget.initial;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Daily goal'),
    content: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('goal-minus'),
          tooltip: 'Fewer pages',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: _v > 1 ? () => setState(() => _v = (_v - (_v > 20 ? 5 : 1)).clamp(1, maxReadGoal)) : null,
        ),
        SizedBox(width: 96, child: Text('$_v pages', key: const Key('goal-value'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
        IconButton(
          key: const Key('goal-plus'),
          tooltip: 'More pages',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _v < maxReadGoal ? () => setState(() => _v = (_v + (_v >= 20 ? 5 : 1)).clamp(1, maxReadGoal)) : null,
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const Key('goal-save'), onPressed: () => Navigator.pop(context, _v), child: const Text('Save')),
    ],
  );
}

class _QuickAdd extends ConsumerStatefulWidget {
  const _QuickAdd();
  @override
  ConsumerState<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends ConsumerState<_QuickAdd> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
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
  Widget build(BuildContext context) {
    // "Add a task" from the app-icon shortcut: put the cursor here
    ref.listen(focusQuickAddProvider, (_, _) {
      // the Home tab may still be switching in: ask again a moment later
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _focus.requestFocus();
      });
    });
    return _field();
  }

  Widget _field() => TextField(
    key: const Key('home-quick-add'),
    controller: _c,
    focusNode: _focus,
    textInputAction: TextInputAction.done,
    onSubmitted: (_) => _submit(),
    decoration: InputDecoration(
      isDense: true,
      hintText: 'Add a task for today…',
      prefixIcon: const Icon(Icons.add),
      suffixIcon: IconButton(
        key: const Key('home-quick-add-go'),
        tooltip: 'Add task',
        icon: const Icon(Icons.keyboard_return),
        onPressed: _submit,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.input),
      ),
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
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              ?trailing,
            ],
          ),
          const SizedBox(height: Space.s8),
          ...children,
        ],
      ),
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
    final events = [
      ...agenda.allDay,
      ...agenda.timed.where((x) => x.kind == ItemKind.event),
    ];
    void openPlanner() {
      ref.read(plannerControllerProvider.notifier).openDay(today);
      context.go(Routes.planner);
    }

    final shown = agenda.tasks.take(_max).toList();
    final empty =
        agenda.tasks.isEmpty && agenda.overdue.isEmpty && events.isEmpty;
    return _Card(
      title: 'Today',
      trailing: TextButton(
        key: const Key('home-open-planner'),
        onPressed: openPlanner,
        child: const Text('Open planner'),
      ),
      children: [
        if (empty)
          Text(
            'Nothing planned for today. Add a task above, or enjoy the free day.',
            style: t.bodySmall,
          ),
        if (agenda.overdue.isNotEmpty) ...[
          Text(
            '${agenda.overdue.length} overdue',
            key: const Key('home-overdue'),
            style: t.labelLarge?.copyWith(color: context.colors.danger),
          ),
          for (final i in agenda.overdue.take(3))
            TaskTile(item: i, showDate: true, onOpen: openPlanner),
          const SizedBox(height: Space.s8),
        ],
        for (final e in events)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s4),
            child: Row(
              children: [
                const Icon(Icons.event, size: 18),
                const SizedBox(width: Space.s8),
                Expanded(
                  child: Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  e.allDay || e.start == null ? 'All day' : timeLabel(e.start!),
                  style: t.bodySmall,
                ),
              ],
            ),
          ),
        for (final i in shown) TaskTile(item: i, onOpen: openPlanner),
        if (agenda.tasks.length > _max)
          TextButton(
            onPressed: openPlanner,
            child: Text('${agenda.tasks.length - _max} more'),
          ),
        if (agenda.tasks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.s4),
            child: Text(
              '$done of ${agenda.tasks.length} done',
              key: const Key('home-progress'),
              style: t.bodySmall,
            ),
          ),
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
    return _Card(
      title: 'Coming up',
      children: [
        for (final e in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s4),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    '${weekdayShort(e.day.weekday)} ${e.day.day}',
                    style: t.labelLarge,
                  ),
                ),
                Icon(
                  e.item.kind == ItemKind.event
                      ? Icons.event
                      : Icons.radio_button_unchecked,
                  size: 16,
                ),
                const SizedBox(width: Space.s8),
                Expanded(
                  child: Text(
                    e.item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (e.item.hasTime && e.item.start != null)
                  Text(timeLabel(e.item.start!), style: t.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReadingCard extends ConsumerWidget {
  const _ReadingCard({required this.books});
  final List<BookRow> books;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final mine = ref.watch(homeReadingOrderProvider) == 'mine';
    final recent = readingBooks(books, mine: mine, limit: 8);
    return _Card(
      title: 'Continue reading',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (books.isNotEmpty)
            PopupMenuButton<String>(
              key: const Key('home-reading-order'),
              tooltip: 'Order',
              icon: const Icon(Icons.swap_vert, size: 20),
              initialValue: mine ? 'mine' : 'recent',
              onSelected: ref.read(homeReadingOrderProvider.notifier).set,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'recent',
                  child: Text('Recently read first'),
                ),
                PopupMenuItem(value: 'mine', child: Text('My order')),
              ],
            ),
          TextButton(
            key: const Key('home-open-library'),
            onPressed: () => context.go(Routes.library),
            child: Text(books.isEmpty ? 'Add PDFs' : 'Library'),
          ),
        ],
      ),
      children: [
        if (books.isEmpty)
          Text(
            'Your library is empty. Add a PDF and it will show up here.',
            style: t.bodySmall,
          )
        else if (recent.isEmpty)
          Text(
            'You haven\'t opened a book yet. ${books.length} ${books.length == 1 ? 'book is' : 'books are'} waiting in your library.',
            style: t.bodySmall,
          )
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recent.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.s12),
              itemBuilder: (_, i) {
                final b = recent[i];
                return BookPeekTarget(
                  book: b,
                  onOpen: () => context.push('${Routes.library}/read/${b.id}'),
                  child: InkWell(
                    key: Key('home-book-${b.id}'),
                    borderRadius: BorderRadius.circular(Radii.input),
                    onTap: () => context.push('${Routes.library}/read/${b.id}'),
                    child: SizedBox(
                      width: 96,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CoverTile(book: b, size: 88),
                          const SizedBox(height: Space.s4),
                          Text(
                            b.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall,
                          ),
                          LinearProgressIndicator(
                            value: readingProgress(b),
                            minHeight: 3,
                          ),
                        ],
                      ),
                    ),
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
    final stale =
        last.value == null ||
        DateTime.now().difference(last.value!).inDays >= 14;
    if (!has || !stale) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s16),
      child: Container(
        key: const Key('home-backup-nudge'),
        padding: const EdgeInsets.all(Space.s12),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Row(
          children: [
            const Icon(Icons.shield_outlined),
            const SizedBox(width: Space.s12),
            Expanded(
              child: Text(
                last.value == null
                    ? 'Your data lives only on this device. Make a backup.'
                    : 'It has been a while since your last backup.',
              ),
            ),
            TextButton(
              onPressed: () => context.go(Routes.settings),
              child: const Text('Back up'),
            ),
          ],
        ),
      ),
    );
  }
}
