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
  Widget build(BuildContext context) => const _Soon(Icons.home_outlined, 'Command Center', 'a later phase', 'Today\'s tasks, upcoming deadlines and your reading progress will gather here.');
}

class LibraryPlaceholder extends StatelessWidget {
  const LibraryPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const _Soon(Icons.auto_stories_outlined, 'Library', 'the next phase', 'Import PDFs, arrange bookshelves and read with annotations.');
}

class PlannerPlaceholder extends StatelessWidget {
  const PlannerPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const _Soon(Icons.calendar_month_outlined, 'Planner', 'after the Library', 'Plan your day, week and year with tasks, time blocks and reminders.');
}
