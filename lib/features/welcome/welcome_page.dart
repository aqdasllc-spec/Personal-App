import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design_system/tokens.dart';

const welcomeDoneKey = 'welcome_done';

class WelcomeStep {
  const WelcomeStep(this.icon, this.title, this.body, this.bullets);
  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;
}

/// The four screens of the first-run tour (also reachable from Settings -> Help).
const welcomeSteps = [
  WelcomeStep(
    Icons.auto_stories_outlined,
    'Welcome to Folio',
    'Your PDF library and your planner in one calm, private place. Everything works offline.',
    [
      'Your files stay yours: Folio keeps its own copy and never changes the original.',
      'Home shows what needs you today and where you stopped reading.',
    ],
  ),
  WelcomeStep(
    Icons.shelves,
    'Your library',
    'Add PDFs, arrange them on shelves, and read with bookmarks, highlights and search.',
    [
      'Press and hold a book for a preview of its first page.',
      'The pen button rearranges: drag books around or onto a shelf name.',
      'The checklist button selects several books at once to tag, move or remove.',
      'The red / green badge on a book is optional cloud sync, one book at a time.',
    ],
  ),
  WelcomeStep(
    Icons.calendar_month_outlined,
    'Plan your days',
    'Tasks, events, sub-tasks, repeats and reminders, by day, week, month or year.',
    [
      'Press and hold a task and drop it on the schedule to give it a time.',
      'Drop it on another day in the Week or Month view to move it.',
      'The clock button on a task picks a time without dragging.',
    ],
  ),
  WelcomeStep(
    Icons.shield_outlined,
    'Yours to keep',
    'Back up everything in one file whenever you like, with an optional password.',
    [
      'Settings -> Backup saves your tasks, events, books, bookmarks and highlights.',
      'Removed books wait 30 days in Settings -> Storage -> Recently removed.',
      'You can reopen this tour and the tips any time from Settings -> Help.',
    ],
  ),
];

/// First-run tour. Marks itself as seen when finished or skipped.
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});
  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  final _pages = PageController();
  int _i = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    try {
      await ref.read(syncedStoreProvider).setState(welcomeDoneKey, '1');
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final last = _i == welcomeSteps.length - 1;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(Space.s8),
                child: TextButton(
                  key: const Key('welcome-skip'),
                  onPressed: _finish,
                  child: Text(last ? 'Close' : 'Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                key: const Key('welcome-pages'),
                controller: _pages,
                onPageChanged: (i) => setState(() => _i = i),
                children: [
                  for (final s in welcomeSteps)
                    Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.s24,
                          vertical: Space.s16,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(s.icon, size: 56, color: c.accent),
                              const SizedBox(height: Space.s16),
                              Text(
                                s.title,
                                style: t.headlineSmall?.copyWith(
                                  fontFamily: 'serif',
                                ),
                              ),
                              const SizedBox(height: Space.s8),
                              Text(s.body, style: t.bodyLarge),
                              const SizedBox(height: Space.s16),
                              for (final b in s.bullets)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: Space.s8,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 6,
                                          right: Space.s8,
                                        ),
                                        child: Icon(
                                          Icons.circle,
                                          size: 6,
                                          color: c.accent,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(b, style: t.bodyMedium),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s24,
                0,
                Space.s24,
                Space.s16,
              ),
              child: Row(
                children: [
                  for (var k = 0; k < welcomeSteps.length; k++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: Space.s8),
                      width: k == _i ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: k == _i ? c.accent : c.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  if (_i > 0)
                    TextButton(
                      key: const Key('welcome-back'),
                      onPressed: () => _pages.previousPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      ),
                      child: const Text('Back'),
                    ),
                  FilledButton(
                    key: const Key('welcome-next'),
                    onPressed: last
                        ? _finish
                        : () => _pages.nextPage(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          ),
                    child: Text(last ? 'Get started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zero-size widget placed on Home: the first time Home is shown it opens the tour.
class WelcomeGate extends ConsumerStatefulWidget {
  const WelcomeGate({super.key});
  @override
  ConsumerState<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends ConsumerState<WelcomeGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    try {
      final done = await ref.read(syncedStoreProvider).state(welcomeDoneKey);
      if (done == '1' || !mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const WelcomePage(),
        ),
      );
    } catch (_) {
      // the tour is a nicety; never block Home
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Settings -> Help: reopen the tour and a cheat-sheet of gestures.
class HelpTiles extends StatelessWidget {
  const HelpTiles({super.key});

  static const tips = [
    ('Library', 'Press and hold a book: preview card with its first page.'),
    (
      'Library',
      'Pen button: rearrange books, drop them on a shelf name, or tap one and use the arrows.',
    ),
    (
      'Library',
      'Checklist button: select several books (slide over them to select many), then tag, move, favourite or remove.',
    ),
    (
      'Library',
      'Sort and filter button: sort order, reading status and tags (Manage renames or merges a tag everywhere).',
    ),
    (
      'Reader',
      'Select text and choose Highlight; the list icon holds bookmarks, highlights, notes and Export.',
    ),
    (
      'Planner',
      'Press and hold a task: drop it on the schedule (time) or on another day (Week / Month).',
    ),
    (
      'Planner',
      'Tap the 2/5 counter on a task to tick its sub-tasks in place.',
    ),
    (
      'Safety',
      'Settings -> Backup: one file, optional password. Settings -> Storage: space use and the 30-day bin.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        key: const Key('settings-welcome'),
        leading: const Icon(Icons.waving_hand_outlined),
        title: const Text('Welcome tour'),
        subtitle: const Text('The four-screen introduction'),
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const WelcomePage(),
          ),
        ),
      ),
      ExpansionTile(
        key: const Key('settings-tips'),
        leading: const Icon(Icons.lightbulb_outline),
        title: const Text('Tips and gestures'),
        children: [
          for (final (area, text) in tips)
            ListTile(dense: true, title: Text(text), subtitle: Text(area)),
        ],
      ),
    ],
  );
}
