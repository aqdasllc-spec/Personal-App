import 'package:flutter/material.dart';

import '../../design_system/components.dart';

// Real (not demo) empty states for modules that land in later phases. They state plainly
// what is coming and offer no fake data or dead buttons.
class _Soon extends StatelessWidget {
  const _Soon(this.icon, this.title, this.phase, this.what);
  final IconData icon;
  final String title, phase, what;
  @override
  Widget build(BuildContext context) => EmptyState(icon: icon, title: title, message: '$what\nPlanned for $phase.');
}

class HomePlaceholder extends StatelessWidget {
  const HomePlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const _Soon(Icons.home_outlined, 'Command Center', 'Phase 5', 'Your goals, deadlines and reading progress will gather here.');
}

class LibraryPlaceholder extends StatelessWidget {
  const LibraryPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const _Soon(Icons.auto_stories_outlined, 'Library', 'Phase 4', 'Import PDFs, arrange bookshelves and read with annotations.');
}

class GoalsPlaceholder extends StatelessWidget {
  const GoalsPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const _Soon(Icons.track_changes_outlined, 'Goals & Projects', 'Phases 2–3', 'Build your own trackers with tables, boards, calendars and more.');
}

class KnowledgePlaceholder extends StatelessWidget {
  const KnowledgePlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const _Soon(Icons.edit_note_outlined, 'Knowledge', 'Phase 5', 'Notes, journals and a graph of how your ideas connect.');
}

class PlannerPlaceholder extends StatelessWidget {
  const PlannerPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const _Soon(Icons.calendar_month_outlined, 'Planner', 'Phase 3', 'Plan your day, week and year with time blocks and reminders.');
}
