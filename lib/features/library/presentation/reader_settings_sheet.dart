import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../application/reader_prefs.dart';

/// Reading settings (like an e-reader's "Aa" menu): page colours, dimming, warmth, scroll direction,
/// tap-to-turn, keep-screen-on and orientation lock.
class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(readerPrefsProvider);
    final set = ref.read(readerPrefsProvider.notifier).update;
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Space.s16,
            0,
            Space.s16,
            Space.s16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Page colours', style: t.titleSmall),
              const SizedBox(height: Space.s8),
              Wrap(
                spacing: Space.s8,
                runSpacing: Space.s8,
                children: [
                  for (final th in ReaderTheme.values)
                    Semantics(
                      label:
                          '${th.label} page colours${p.theme == th ? ', selected' : ''}',
                      button: true,
                      child: InkWell(
                        key: Key('reader-theme-${th.name}'),
                        borderRadius: BorderRadius.circular(Radii.card),
                        onTap: () => set((x) => x.copyWith(theme: th)),
                        child: Container(
                          width: 76,
                          padding: const EdgeInsets.all(Space.s8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: p.theme == th ? c.accent : c.border,
                              width: p.theme == th ? 3 : 1,
                            ),
                            borderRadius: BorderRadius.circular(Radii.card),
                          ),
                          child: Column(
                            children: [
                              Container(
                                height: 36,
                                width: double.infinity,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: th.swatch.$1,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: c.border),
                                ),
                                child: Text(
                                  'Aa',
                                  style: TextStyle(
                                    color: th.swatch.$2,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(height: Space.s4),
                              Text(th.label, style: t.bodySmall),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.s16),
              _SliderRow(
                label: 'Dim',
                icon: Icons.brightness_low,
                value: p.dim / 0.7,
                sliderKey: const Key('reader-dim'),
                onChanged: (v) => set((x) => x.copyWith(dim: v * 0.7)),
              ),
              _SliderRow(
                label: 'Warm light',
                icon: Icons.wb_twilight,
                value: p.warmth,
                sliderKey: const Key('reader-warmth'),
                onChanged: (v) => set((x) => x.copyWith(warmth: v)),
              ),
              const SizedBox(height: Space.s8),
              Text('Turning pages', style: t.titleSmall),
              const SizedBox(height: Space.s8),
              SegmentedButton<ReaderScroll>(
                key: const Key('reader-scroll'),
                showSelectedIcon: false,
                segments: [
                  for (final s in ReaderScroll.values)
                    ButtonSegment(value: s, label: Text(s.label)),
                ],
                selected: {p.scroll},
                onSelectionChanged: (s) =>
                    set((x) => x.copyWith(scroll: s.first)),
              ),
              SwitchListTile(
                key: const Key('reader-tapturn'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Tap the page edges to turn'),
                subtitle: const Text(
                  'Left / right edge = previous / next page. Tap the middle to hide the toolbar.',
                ),
                value: p.tapTurn,
                onChanged: (v) => set((x) => x.copyWith(tapTurn: v)),
              ),
              SwitchListTile(
                key: const Key('reader-awake'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep the screen on while reading'),
                value: p.keepAwake,
                onChanged: (v) => set((x) => x.copyWith(keepAwake: v)),
              ),
              const SizedBox(height: Space.s8),
              Text('Screen orientation', style: t.titleSmall),
              const SizedBox(height: Space.s8),
              SegmentedButton<ReaderOrientation>(
                key: const Key('reader-orientation'),
                showSelectedIcon: false,
                segments: [
                  for (final o in ReaderOrientation.values)
                    ButtonSegment(value: o, label: Text(o.label)),
                ],
                selected: {p.orientation},
                onSelectionChanged: (s) =>
                    set((x) => x.copyWith(orientation: s.first)),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('reader-reset'),
                  onPressed: () => set((_) => const ReaderPrefs()),
                  child: const Text('Reset to defaults'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.sliderKey,
    required this.onChanged,
  });
  final String label;
  final IconData icon;
  final double value;
  final Key sliderKey;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: Space.s8),
      SizedBox(width: 84, child: Text(label)),
      Expanded(
        child: Slider(
          key: sliderKey,
          value: value.clamp(0.0, 1.0),
          onChanged: onChanged,
          semanticFormatterCallback: (v) =>
              '$label ${(v * 100).round()} percent',
        ),
      ),
    ],
  );
}
