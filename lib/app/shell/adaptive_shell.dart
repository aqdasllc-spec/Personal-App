import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/components.dart';
import '../../design_system/tokens.dart';
import '../providers.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon, selectedIcon;
}

const _dests = [
  _Dest('Home', Icons.home_outlined, Icons.home),
  _Dest('Library', Icons.auto_stories_outlined, Icons.auto_stories),
  _Dest('Goals & Projects', Icons.track_changes_outlined, Icons.track_changes),
  _Dest('Knowledge', Icons.edit_note_outlined, Icons.edit_note),
  _Dest('Planner', Icons.calendar_month_outlined, Icons.calendar_month),
  _Dest('Settings', Icons.settings_outlined, Icons.settings),
];

/// Sidebar (expanded) · rail (medium) · bottom bar (compact). Settings sits in the bottom
/// bar's overflow on compact screens (profile button in the top bar).
class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final wc = WindowClass.of(width);
    final c = context.colors;
    final idx = shell.currentIndex;

    final top = _TopBar(compact: wc == WindowClass.compact, onSettings: () => _go(5));
    final body = Column(children: [top, Expanded(child: shell)]);

    switch (wc) {
      case WindowClass.expanded:
        return Scaffold(
          body: Row(children: [
            Container(
              width: 240,
              decoration: BoxDecoration(color: c.surface, border: Border(right: BorderSide(color: c.border))),
              child: SafeArea(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.s24, Space.s24, Space.s16, Space.s16),
                    child: Text('Folio', style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  for (var i = 0; i < _dests.length; i++)
                    _SidebarItem(dest: _dests[i], selected: i == idx, onTap: () => _go(i)),
                ]),
              ),
            ),
            Expanded(child: body),
          ]),
        );
      case WindowClass.medium:
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: idx,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              destinations: [for (final d in _dests) NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label, textAlign: TextAlign.center))],
            ),
            VerticalDivider(color: c.border),
            Expanded(child: body),
          ]),
        );
      case WindowClass.compact:
        return Scaffold(
          body: SafeArea(child: body),
          bottomNavigationBar: NavigationBar(
            selectedIndex: idx.clamp(0, 4),
            onDestinationSelected: _go,
            destinations: [for (final d in _dests.take(5)) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label.split(' ').first)],
          ),
        );
    }
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.dest, required this.selected, required this.onTap});
  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s12, vertical: 1),
      child: Material(
        color: selected ? c.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Semantics(
            selected: selected,
            button: true,
            excludeSemantics: true, // announce once ("Home, selected, button"), not label + child text
            label: dest.label,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s12, vertical: Space.s12),
              child: Row(children: [
                Icon(selected ? dest.selectedIcon : dest.icon, size: 20, color: selected ? c.accent : c.textMuted),
                const SizedBox(width: Space.s12),
                Expanded(
                  child: Text(dest.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: selected ? c.accent : c.textMuted, fontWeight: selected ? FontWeight.w600 : null)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.compact, required this.onSettings});
  final bool compact;
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final status = ref.watch(syncControllerProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s16, vertical: Space.s8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        if (compact) Text('Folio', style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        SyncChip(phase: status.phase, pending: status.pending),
        if (compact) IconButton(tooltip: 'Settings', onPressed: onSettings, icon: const Icon(Icons.account_circle_outlined)),
      ]),
    );
  }
}
