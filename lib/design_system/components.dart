import 'package:flutter/material.dart';

import 'tokens.dart';

/// Empty state: one sentence and one primary action (docs/02 §6).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(Space.s24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: c.textMuted),
            const SizedBox(height: Space.s16),
            Text(title, style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: Space.s8),
            Text(message, style: t.bodyMedium?.copyWith(color: c.textMuted), textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: Space.s24),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Sync state shown in the top bar. Calm by default: only problems use colour.
enum SyncPhase { synced, syncing, offline, attention, localOnly }

class SyncChip extends StatelessWidget {
  const SyncChip({super.key, required this.phase, this.pending = 0, this.detail});
  final SyncPhase phase;
  final int pending;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, color) = switch (phase) {
      SyncPhase.synced => ('Synced', c.ok),
      SyncPhase.syncing => ('Syncing${pending > 0 ? ' $pending' : ''}', c.info),
      SyncPhase.offline => ('Offline${pending > 0 ? ' · $pending pending' : ''}', c.warn),
      SyncPhase.attention => ('Needs attention', c.danger),
      SyncPhase.localOnly => ('Local only', c.textMuted),
    };
    return Semantics(
      label: 'Sync status: $label${detail != null ? ', $detail' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.s12, vertical: Space.s4),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: Space.s8),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text)),
        ]),
      ),
    );
  }
}
